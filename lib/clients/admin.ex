defmodule KeycloakEx.Client.Admin do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @otp_app opts[:otp_app]
      use OAuth2.Strategy

      def config() do
        Application.get_env(@otp_app, __MODULE__, [])
      end

      def new do
        conf = config()

        OAuth2.Client.new(
          strategy: OAuth2.Strategy.Password,
          client_id: conf[:client_id],
          token_url: "#{conf[:host_uri]}/realms/#{conf[:realm]}/protocol/openid-connect/token"
        )
        |> OAuth2.Client.put_serializer("application/json", Jason)
      end

      def get_token(headers \\ []) do
        conf = config()

        OAuth2.Client.get_token!(
          new(),
          [username: conf[:username], password: conf[:password]],
          headers
        )
      end

      # Not needed for Login client
      def authorize_url(_client, _params \\ []) do
        nil
      end

      def get_token(_client, _params, _headers) do
        nil
      end

      defp response({:ok, resp}), do: Jason.decode!(resp.body)
      defp response(resp), do: resp

      def get_request_realm(realm, url, body \\ nil) do
        conf = config()

        OAuth2.Client.get(
          new(),
          "#{conf[:host_uri]}/admin/realms/#{realm}/#{url}",
          [
            {"Authorization", "Bearer #{get_token().token.access_token}"},
            {"Accept", "application/json"}
          ]
        )
      end

      defp post_request_realm(realm, url, body) do
        conf = config()

        OAuth2.Client.post(
          new(),
          "#{conf[:host_uri]}/admin/realms/#{realm}/#{url}",
          body,
          [
            {"Authorization", "Bearer #{get_token().token.access_token}"},
            {"Content-Type", "application/json"},
            {"Accept", "application/json"}
          ]
        )
      end

      defp put_request_realm(realm, url, body) do
        conf = config()

        OAuth2.Client.put(
          new(),
          "#{conf[:host_uri]}/admin/realms/#{realm}/#{url}",
          body,
          [
            {"Authorization", "Bearer #{get_token().token.access_token}"},
            {"Content-Type", "application/json"},
            {"Accept", "application/json"}
          ]
        )
      end

      defp delete_request_realm(realm, url) do
        conf = config()

        OAuth2.Client.delete(
          new(),
          "#{conf[:host_uri]}/admin/realms/#{realm}/#{url}",
          [
            {"Authorization", "Bearer #{get_token().token.access_token}"},
            {"Accept", "application/json"}
          ]
        )
      end

      @doc "Creates a Keycloak user. Returns {:ok, user_id} on success, {:error, reason} on failure."
      def create_user(realm, attrs) do
        case post_request_realm(realm, "users", attrs) do
          {:ok, %OAuth2.Response{status_code: 201, headers: headers}} ->
            case List.keyfind(headers, "location", 0) do
              {_, location} -> {:ok, location |> String.split("/") |> List.last()}
              nil -> {:error, "No Location header in create_user response"}
            end

          {:ok, %OAuth2.Response{status_code: 409}} ->
            {:error, "User already exists in Keycloak"}

          {:ok, %OAuth2.Response{status_code: status}} ->
            {:error, "create_user unexpected status: #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc "Triggers Keycloak to send an execute-actions email (e.g. UPDATE_PASSWORD) to the given user."
      def execute_actions_email(realm, user_id, actions, opts \\ []) do
        redirect_uri = opts[:redirect_uri]
        client_id = opts[:client_id]

        qs =
          URI.encode_query(
            Enum.reject(
              [redirect_uri: redirect_uri, client_id: client_id],
              fn {_, v} -> is_nil(v) end
            )
          )

        url =
          if qs != "",
            do: "users/#{user_id}/execute-actions-email?#{qs}",
            else: "users/#{user_id}/execute-actions-email"

        case put_request_realm(realm, url, actions) do
          {:ok, %OAuth2.Response{status_code: 204}} ->
            :ok

          {:ok, %OAuth2.Response{status_code: status}} ->
            {:error, "execute_actions_email unexpected status: #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc "Deletes a Keycloak user. Returns :ok or {:error, reason}. Used for compensating rollback."
      def delete_user(realm, user_id) do
        case delete_request_realm(realm, "users/#{user_id}") do
          {:ok, %OAuth2.Response{status_code: status}} when status in [204, 404] ->
            :ok

          {:ok, %OAuth2.Response{status_code: status}} ->
            {:error, "delete_user unexpected status: #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
      end

      def get_clients(realm) do
        get_request_realm(realm, "clients")
      end

      def get_users(realm) do
        get_request_realm(realm, "users")
      end

      def get_user_by_username(realm, username) do
        get_request_realm(realm, "users?username=#{username}")
      end

      def get_user(realm, id) do
        get_request_realm(realm, "users/#{id}")
      end

      def get_user_count(realm) do
        get_request_realm(realm, "users/count")
      end

      def get_users_profile(realm) do
        get_request_realm(realm, "users/profile")
      end
    end
  end
end
