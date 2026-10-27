defmodule PhoenixKitUserConnections.Integration.ConnectionRequestAuthorizationTest do
  @moduledoc """
  Only a request's recipient may accept or reject it; only its requester may
  cancel it. Enforced in the context, so a caller that passes someone else's
  request uuid — the LiveView forwards whatever `phx-value-id` the browser
  sends — gets `{:error, :not_recipient}` and the row is left alone.
  """
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias PhoenixKitUserConnections.Connection
  alias PhoenixKitUserConnections.Test.Repo

  @moduletag :integration

  setup do
    pid = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    requester = user_fixture()
    recipient = user_fixture()
    outsider = user_fixture()

    {:ok, connection} = PhoenixKitUserConnections.request_connection(requester, recipient)

    {:ok, requester: requester, recipient: recipient, outsider: outsider, connection: connection}
  end

  defp user_fixture do
    n = System.unique_integer([:positive])

    %PhoenixKit.Users.Auth.User{}
    |> Ecto.Changeset.change(%{
      email: "uc-#{n}@example.com",
      hashed_password: "not-a-real-hash",
      is_active: true
    })
    |> Repo.insert!()
  end

  defp status(connection), do: Repo.get(Connection, connection.uuid) |> then(&(&1 && &1.status))

  test "someone else cannot accept or reject the request", ctx do
    for actor <- [ctx.outsider, ctx.requester] do
      assert {:error, :not_recipient} =
               PhoenixKitUserConnections.accept_connection(actor, ctx.connection.uuid)

      assert {:error, :not_recipient} =
               PhoenixKitUserConnections.reject_connection(actor, ctx.connection.uuid)
    end

    # A struct is re-read, not trusted.
    assert {:error, :not_recipient} =
             PhoenixKitUserConnections.accept_connection(
               ctx.outsider,
               %{ctx.connection | recipient_uuid: ctx.outsider.uuid}
             )

    assert {:error, :not_recipient} =
             PhoenixKitUserConnections.accept_connection(nil, ctx.connection.uuid)

    assert status(ctx.connection) == "pending"
  end

  test "the recipient accepts", ctx do
    assert {:ok, _} = PhoenixKitUserConnections.accept_connection(ctx.recipient, ctx.connection)
    assert status(ctx.connection) == "accepted"
  end

  test "the recipient rejects", ctx do
    assert {:ok, _} =
             PhoenixKitUserConnections.reject_connection(ctx.recipient, ctx.connection.uuid)

    assert status(ctx.connection) == nil
  end

  test "only the requester cancels", ctx do
    assert {:error, :not_requester} =
             PhoenixKitUserConnections.cancel_request(ctx.recipient, ctx.connection.uuid)

    assert {:error, :not_requester} =
             PhoenixKitUserConnections.cancel_request(ctx.outsider, ctx.connection.uuid)

    assert {:ok, _} =
             PhoenixKitUserConnections.cancel_request(ctx.requester, ctx.connection.uuid)

    assert status(ctx.connection) == nil
  end

  test "an accepted request cannot be accepted again", ctx do
    {:ok, _} = PhoenixKitUserConnections.accept_connection(ctx.recipient, ctx.connection.uuid)

    assert {:error, :not_pending} =
             PhoenixKitUserConnections.accept_connection(ctx.recipient, ctx.connection.uuid)
  end
end
