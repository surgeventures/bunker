defmodule Bunker.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/surgeventures/bunker"

  def project do
    [
      app: :bunker,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "Bunker",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Bunker.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:ecto_sql, "~> 3.10"},
      {:telemetry, "~> 0.4 or ~> 1.0"},

      # Test dependencies
      {:mimic, "~> 1.7", only: :test},

      # Documentation
      {:ex_doc, "~> 0.29", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Automatically detect dangerous operations (like gRPC calls, external APIs)
    within Ecto transactions using telemetry-based monitoring.
    """
  end

  defp package do
    [
      name: "bunker",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["Your Name"]
    ]
  end

  defp docs do
    [
      main: "Bunker",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
