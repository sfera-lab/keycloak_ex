defmodule KeycloakEx.TokenVerifier do
  @moduledoc """
  Module to verify Keycloak-issued JWT tokens without introspection.
  """
  @cache_ttl :timer.minutes(60)

  use GenServer

  alias JOSE.{JWK, JWT}

  ## Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def verify_token(token) when is_binary(token) do
    case get_jwks() do
      {:ok, jwks} -> verify_with_jwks(token, jwks)
      {:error, reason} -> {:error, reason}
    end
  end

  ## GenServer Callbacks

  def init(opts) do
    schedule_refresh()
    {:ok, {opts[:keycloak_client], fetch_jwks(opts[:keycloak_client])}}
  end

  def handle_info(:refresh_jwks, {keycloak_client, _}) do
    keys = fetch_jwks(keycloak_client)
    schedule_refresh()
    {:noreply, {keycloak_client, keys}}
  end

  ## Helper Functions

  defp schedule_refresh do
    Process.send_after(self(), :refresh_jwks, @cache_ttl)
  end

  def fetch_jwks(client) do
    case client.get_jws() do
      {:ok, %OAuth2.Response{status_code: 200, body: body}} ->
        case body do
          %{"keys" => keys} -> keys |> IO.inspect()
          _ -> []
        end
      _ -> []
    end
  end

  defp get_jwks do
    GenServer.call(__MODULE__, :get_jwks)
  end

  def handle_call(:get_jwks, _from, {_, jwks} = state) do
    {:reply, {:ok, jwks}, state}
  end

  defp verify_with_jwks(token, jwks) do
    with {:ok, %JWT{fields: claims}, _key} <- get_valid_key(token, jwks),
         {:ok, _} <- validate_claims(claims) do
      {:ok, claims}
    else
      _ -> {:error, "Invalid token"}
    end
  end

  defp get_valid_key(token, jwks) do
    with {:ok, %JWT{} = jwt, %{"kid" => kid}} <- decode_token(token),
         key <- Enum.find(jwks, fn k -> k["kid"] == kid end),
         jwk <- JWK.from(key),
         true <- JOSE.JWT.verify_strict(jwk, ["RS256"], token) do
      {:ok, jwt, jwk}
    else
      _ -> {:error, "Invalid key"}
    end
  end

  defp decode_token(token) do
    case JOSE.JWT.peek_payload(token) do
      %JOSE.JWT{} = jwt -> {:ok, jwt, JOSE.JWT.peek_protected(token)}
      _ -> {:error, "Invalid JWT"}
    end
  end

  defp validate_claims(%{"exp" => exp}) do
    if exp > :os.system_time(:seconds) do
      {:ok, "Valid token"}
    else
      {:error, "Token expired"}
    end
  end
end
