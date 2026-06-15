defmodule KeycloakEx.VerifyOfflineBearerToken do
  @moduledoc """
  Verifies a Keycloak access token from the `Authorization: Bearer` header
  *offline* - against the realm JWKS cached by `KeycloakEx.TokenVerifier` -
  without calling Keycloak's token introspection endpoint on every request.

  This is the offline counterpart to `KeycloakEx.VerifyBearerToken` (which
  introspects). It is ideal for a stateless resource server / API that receives
  JWT access tokens issued to a separate front-end client: tokens are verified
  locally, so Keycloak is not in the per-request hot path.

  On top of the signature and `exp` check done by `KeycloakEx.TokenVerifier`,
  this plug validates the standard claims that verifier leaves out:

    * `iss` - must equal the realm issuer (`"\#{host_uri}/realms/\#{realm}"`)
    * `aud` - must contain the expected audience (the client's `client_id` by
      default; Keycloak may emit a single string or a list)
    * `nbf` - if present, the token must not be used before it is valid

  ## Requirements

  `KeycloakEx.TokenVerifier` must be running, started with the same client (it
  fetches and caches the realm JWKS):

      {KeycloakEx.TokenVerifier, keycloak_client: MyApp.KeycloakClient}

  ## Usage

      plug KeycloakEx.VerifyOfflineBearerToken, client: MyApp.KeycloakClient

  On success the verified claims are assigned to `conn.assigns.token_claims`.
  On failure the connection is halted with a `401` JSON response.

  ## Options

    * `:client` (required) - the `KeycloakEx.Client.User` module. Its config
      (`host_uri`, `realm`, `client_id`) is used to derive the expected `iss`
      and `aud`.
    * `:audience` - override the expected audience (defaults to the client's
      `client_id`).
    * `:issuer` - override the expected issuer (defaults to
      `"\#{host_uri}/realms/\#{realm}"`).
  """
  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(conn, opts) do
    client = Keyword.fetch!(opts, :client)

    case authorize(conn, client, opts) do
      {:ok, claims} ->
        assign(conn, :token_claims, claims)

      {:error, reason} ->
        Logger.debug("[Plug][KeycloakEx.VerifyOfflineBearerToken] - #{reason}")
        unauthorized(conn)
    end
  end

  defp authorize(conn, client, opts) do
    with {:ok, token} <- fetch_bearer(conn),
         {:ok, claims} <- KeycloakEx.TokenVerifier.verify_token(token),
         :ok <- check_claim(claims, "iss", issuer(client, opts)),
         :ok <- check_audience(claims, audience(client, opts)),
         :ok <- check_not_before(claims) do
      {:ok, claims}
    end
  end

  defp fetch_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _ -> {:error, "missing or malformed Authorization: Bearer header"}
    end
  end

  defp check_claim(claims, key, expected) do
    if Map.get(claims, key) == expected,
      do: :ok,
      else: {:error, "#{key} #{inspect(Map.get(claims, key))} != #{inspect(expected)}"}
  end

  # Keycloak's `aud` claim may be a single string or a list of audiences.
  defp check_audience(claims, expected) do
    valid? =
      case Map.get(claims, "aud") do
        auds when is_list(auds) -> expected in auds
        aud -> aud == expected
      end

    if valid?, do: :ok, else: {:error, "aud does not contain #{inspect(expected)}"}
  end

  # `nbf` is optional; absent means there is no not-before constraint.
  defp check_not_before(%{"nbf" => nbf}) when is_integer(nbf) do
    if nbf <= System.system_time(:second), do: :ok, else: {:error, "token not yet valid (nbf)"}
  end

  defp check_not_before(_), do: :ok

  defp issuer(client, opts) do
    Keyword.get_lazy(opts, :issuer, fn ->
      conf = client.config()
      "#{conf[:host_uri]}/realms/#{conf[:realm]}"
    end)
  end

  defp audience(client, opts) do
    Keyword.get_lazy(opts, :audience, fn -> client.config()[:client_id] end)
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{"error" => "401", "error_description" => "Unauthorised"}))
    |> halt()
  end
end
