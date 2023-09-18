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
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mint, "~> 1.4"},
      {:mint_web_socket, "~> 1.0"},
      {:req, "~> 0.4.3"},
      {:slack_web_api, github: "mhsdef/slack_web_api"}
    ]
  end
end
