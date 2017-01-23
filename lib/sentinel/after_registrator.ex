defmodule Sentinel.AfterRegistrator do
  @moduledoc """
  Handles the email sending logic after a new user is registered to the platform
  """
  alias Sentinel.Config
  alias Sentinel.Mailer
  alias Sentinel.Changeset.PasswordResetter

  def confirmable_and_invitable(user, confirmation_token) do
    case {confirmable?, invitable?} do # NOTE move this from a case to private methods?
      {false, false} -> # not confirmable or invitable
        {:ok, user}

      {_confirmable, :true} -> # must be invited
        {password_reset_token, changeset} =
          Sentinel.Ueberauth
          |> Config.repo.get_by!(provider: "identity", user_id: user.id)
          |> PasswordResetter.create_changeset
        Config.repo.update!(changeset)

        Mailer.send_invite_email(user, {confirmation_token, password_reset_token})
        {:ok, user}

      {:required, _invitable} -> # must be confirmed
        Mailer.send_welcome_email(user, confirmation_token)
        {:ok, user}

      {_confirmable_default, _invitable} -> # default behavior, optional confirmable, not invitable
        Mailer.send_welcome_email(user, confirmation_token)
        {:ok, user}
    end
  end

  defp confirmable? do
    case Config.confirmable do
      :required -> :required
      :false -> :false
      _ -> :optional
    end
  end

  defp invitable? do
    Config.invitable
  end
end
