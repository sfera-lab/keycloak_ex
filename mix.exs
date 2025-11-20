defmodule KeycloakEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :keycloak_ex,
      version: "0.1.4",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "keycloak_ex",
      source_url: "https://github.com/root-mt/keycloak_ex"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
      # mod: {Keycloak.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:oauth2, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.0"},
      {:phoenix, "~> 1.5", optional: true},
      {:mint, "~> 1.0"},
      {:jose, "~> 1.11"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:testcontainers, "~> 1.13", only: :test}
    ]
  end

  defp description() do
    "A Keycloak integration"
  end

  defp package() do
    [
      # This option is only needed when you don't want to use the OTP application name
      name: "keycloak_ex",
      # These are the default files included in the package
      files: ~w(lib .formatter.exs mix.exs README* LICENSE),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/root-mt/keycloak_ex"}
    ]
  end
end
