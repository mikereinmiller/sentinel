defmodule Sentinel.Controllers.Html.AuthController do
  @moduledoc """
  Handles the session create and destroy actions
  """
  require Ueberauth
  use Phoenix.Controller
  alias Sentinel.AfterRegistrator
  alias Sentinel.Config
  alias Sentinel.Ueberauthenticator

  plug Ueberauth
  plug :put_layout, {Config.layout_view, Config.layout}
  plug Guardian.Plug.VerifySession when action in [:delete]
  plug Guardian.Plug.EnsureAuthenticated, %{handler: Config.auth_handler} when action in [:delete]
  plug Guardian.Plug.LoadResource when action in [:delete]

  def request(conn, _params) do
    changeset = Sentinel.Session.changeset(%Sentinel.Session{})
    render(conn, Sentinel.SessionView, "new.html", %{conn: conn, changeset: changeset, providers: Config.ueberauth_providers})
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    failed_to_authenticate(conn)
  end
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Ueberauthenticator.ueberauthenticate(auth) do
      {:ok, %{user: user, confirmation_token: confirmation_token}} ->
        new_user(conn, user, confirmation_token)
      {:ok, user} -> existing_user(conn, user)
      {:error, _errors} ->
        failed_to_authenticate(conn)
    end
  end

  defp failed_to_authenticate(conn) do
    changeset = Sentinel.Session.changeset(%Sentinel.Session{})
    conn
    |> put_status(401)
    |> put_flash(:error, "Failed to authenticate")
    |> render(Sentinel.SessionView, "new.html", %{conn: conn, changeset: changeset, providers: Config.ueberauth_providers})
  end

  defp new_user(conn, user, confirmation_token) do
    {:ok, user} = AfterRegistrator.confirmable_and_invitable(user, confirmation_token)
    ueberauth = Config.repo.get_by(Sentinel.Ueberauth, user_id: user.id)

    if ueberauth.provider == "identity" && is_nil(ueberauth.hashed_password) do
      conn
      |> put_flash(:info, "Successfully invited user")
      |> redirect(to: Config.router_helper.user_path(Config.endpoint, :new))
    else
      case Config.confirmable do
        :required ->
          conn
          |> put_flash(:info, "You must confirm your account to continue. You will receive an email with instructions for how to confirm your email address in a few minutes.")
          |> redirect(to: "/")
        :false ->
          conn
          |> Guardian.Plug.sign_in(user)
          |> put_flash(:info, "Signed up")
          |> redirect(to: Config.router_helper.account_path(Config.endpoint, :edit))
        _ ->
          conn
          |> Guardian.Plug.sign_in(user)
          |> put_flash(:info, "You will receive an email with instructions for how to confirm your email address in a few minutes.")
          |> redirect(to: Config.router_helper.account_path(Config.endpoint, :edit))
      end
    end
  end

  defp existing_user(conn, user) do
    conn
    |> Guardian.Plug.sign_in(user)
    |> put_flash(:info, "Logged in")
    |> redirect(to: Config.router_helper.account_path(Config.endpoint, :edit))
  end

  @doc """
  Destroy the active session.
  Will delete the authentication token from the user table.
  """
  def delete(conn, _params) do
    conn
    |> Guardian.Plug.sign_out
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: "/")
  end

  @doc """
  Log in as an existing user.
  """
  def create(conn, %{"session" => %{"email" => email, "password" => password}}) do
    auth = %Ueberauth.Auth{
      provider: :identity,
      credentials: %Ueberauth.Auth.Credentials{
        other: %{
          password: password
        }
      },
      uid: email
    }

    case Ueberauthenticator.ueberauthenticate(auth) do
      {:ok, user} ->
        conn
        |> Guardian.Plug.sign_in(user)
        |> put_flash(:info, "Logged in")
        |> redirect(to: Config.router_helper.account_path(Config.endpoint, :edit))
      {:error, _errors} ->
        conn
        |> put_flash(:error, "Unknown username or password")
        |> redirect(to: Config.router_helper.auth_path(Config.endpoint, :new))
    end
  end
end
