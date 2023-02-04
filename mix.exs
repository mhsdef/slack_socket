defmodule SlackSocket.MixProject do
  use Mix.Project

  def project do
    [
      app: :slack_socket,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SlackSocket.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mint_web_socket, "~> 1.0"},
      {:nimble_pool, "~> 0.2.6"},
      {:req, "~> 0.3.5"},
      {:slack_web_api, github: "defmhs/slack_web_api"}
    ]
  end
end
