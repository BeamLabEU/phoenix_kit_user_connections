defmodule PhoenixKitUserConnections do
  @moduledoc """
  User connections module — social relationships system.

  Provides a complete social relationships system with two types of relationships:

  1. **Follows** - One-way relationships (User A follows User B, no consent needed)
  2. **Connections** - Two-way mutual relationships (both users must accept)

  Plus **blocking** functionality to prevent unwanted interactions.

  ## Usage Examples

  ### In a User Profile Page

      # Get relationship for rendering follow/connect buttons
      relationship = PhoenixKitUserConnections.get_relationship(current_user, profile_user)

      # Display counts
      followers = PhoenixKitUserConnections.followers_count(profile_user)
      following = PhoenixKitUserConnections.following_count(profile_user)
      connections = PhoenixKitUserConnections.connections_count(profile_user)

  ## Business Rules

  ### Following
  - Cannot follow yourself
  - Cannot follow if blocked (either direction)
  - Instant, no approval needed

  ### Connections
  - Cannot connect with yourself
  - Cannot connect if blocked
  - Requires acceptance from recipient
  - If A requests B while B has pending request to A → auto-accept both

  ### Blocking
  - Blocking removes any existing follow/connection between the users
  - Blocked user cannot follow, connect, or view profile
  - Blocking is one-way (A blocks B doesn't mean B blocks A)
  """

  use PhoenixKit.Module

  import Ecto.Query, warn: false
  require Logger

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKit.Settings
  alias PhoenixKitUserConnections.Block
  alias PhoenixKitUserConnections.BlockHistory
  alias PhoenixKitUserConnections.Connection
  alias PhoenixKitUserConnections.ConnectionHistory
  alias PhoenixKitUserConnections.Follow
  alias PhoenixKitUserConnections.FollowHistory

  # ===== MODULE STATUS =====

  @impl PhoenixKit.Module
  def enabled? do
    Settings.get_boolean_setting("connections_enabled", false)
  end

  @impl PhoenixKit.Module
  def enable_system do
    Settings.update_boolean_setting_with_module("connections_enabled", true, module_key())
  end

  @impl PhoenixKit.Module
  def disable_system do
    Settings.update_boolean_setting_with_module("connections_enabled", false, module_key())
  end

  @impl PhoenixKit.Module
  def get_config do
    %{
      enabled: enabled?(),
      follows_count: get_total_follows_count(),
      connections_count: get_total_connections_count(),
      pending_count: get_total_pending_count(),
      blocks_count: get_total_blocks_count()
    }
  end

  # ============================================================================
  # Module Behaviour Callbacks
  # ============================================================================

  @impl PhoenixKit.Module
  def module_key, do: "connections"

  @impl PhoenixKit.Module
  def module_name, do: "Connections"

  @impl PhoenixKit.Module
  def version, do: "0.1.2"

  @impl PhoenixKit.Module
  def permission_metadata do
    %{
      key: "connections",
      label: "Connections",
      icon: "hero-link",
      description: "Social relationships with follows, mutual connections, and blocking"
    }
  end

  @impl PhoenixKit.Module
  def admin_tabs do
    [
      Tab.new!(
        id: :admin_connections,
        label: "Connections",
        icon: "hero-link",
        path: "connections",
        priority: 600,
        level: :admin,
        permission: "connections",
        match: :prefix,
        group: :admin_modules,
        live_view: {PhoenixKitUserConnections.Web.Connections, :index}
      )
    ]
  end

  @impl PhoenixKit.Module
  def css_sources, do: [:phoenix_kit_user_connections]

  @doc "Returns statistics for the admin overview page."
  def get_stats do
    %{
      follows: get_total_follows_count(),
      connections: get_total_connections_count(),
      pending: get_total_pending_count(),
      blocks: get_total_blocks_count()
    }
  end

  # ===== FOLLOWS =====

  @doc """
  Creates a follow relationship.

  User A follows User B. No consent is required from User B.
  """
  def follow(follower, followed) do
    follower_uuid = get_user_uuid(follower)
    followed_uuid = get_user_uuid(followed)

    cond do
      follower_uuid == followed_uuid ->
        {:error, :self_follow}

      blocked?(followed_uuid, follower_uuid) || blocked?(follower_uuid, followed_uuid) ->
        {:error, :blocked}

      following?(follower_uuid, followed_uuid) ->
        {:error, :already_following}

      true ->
        do_follow(follower_uuid, followed_uuid)
    end
  end

  defp do_follow(follower_uuid, followed_uuid) do
    repo().transaction(fn ->
      case %Follow{}
           |> Follow.changeset(%{follower_uuid: follower_uuid, followed_uuid: followed_uuid})
           |> repo().insert() do
        {:ok, follow} ->
          log_follow_history(follower_uuid, followed_uuid, "follow")
          follow

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  @doc "Removes a follow relationship."
  def unfollow(follower, followed) do
    follower_uuid = get_user_uuid(follower)
    followed_uuid = get_user_uuid(followed)

    case get_follow(follower_uuid, followed_uuid) do
      nil -> {:error, :not_following}
      follow -> do_unfollow(follow)
    end
  end

  defp do_unfollow(follow) do
    repo().transaction(fn ->
      case repo().delete(follow) do
        {:ok, deleted} ->
          log_follow_history(follow.follower_uuid, follow.followed_uuid, "unfollow")
          deleted

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  @doc "Checks if user A is following user B."
  def following?(follower, followed) do
    follower_uuid = get_user_uuid(follower)
    followed_uuid = get_user_uuid(followed)

    Follow
    |> where([f], f.follower_uuid == ^follower_uuid and f.followed_uuid == ^followed_uuid)
    |> repo().exists?()
  end

  @doc "Returns all followers of a user."
  def list_followers(user, opts \\ []) do
    user_uuid = get_user_uuid(user)
    preload = Keyword.get(opts, :preload, true)

    query =
      Follow
      |> where([f], f.followed_uuid == ^user_uuid)
      |> order_by([f], desc: f.inserted_at)
      |> maybe_limit(opts[:limit])
      |> maybe_offset(opts[:offset])

    query = if preload, do: preload(query, [:follower]), else: query

    repo().all(query)
  end

  @doc "Returns all users that a user is following."
  def list_following(user, opts \\ []) do
    user_uuid = get_user_uuid(user)
    preload = Keyword.get(opts, :preload, true)

    query =
      Follow
      |> where([f], f.follower_uuid == ^user_uuid)
      |> order_by([f], desc: f.inserted_at)
      |> maybe_limit(opts[:limit])
      |> maybe_offset(opts[:offset])

    query = if preload, do: preload(query, [:followed]), else: query

    repo().all(query)
  end

  @doc "Returns the count of followers for a user."
  def followers_count(user) do
    user_uuid = get_user_uuid(user)

    Follow
    |> where([f], f.followed_uuid == ^user_uuid)
    |> repo().aggregate(:count)
  end

  @doc "Returns the count of users that a user is following."
  def following_count(user) do
    user_uuid = get_user_uuid(user)

    Follow
    |> where([f], f.follower_uuid == ^user_uuid)
    |> repo().aggregate(:count)
  end

  # ===== CONNECTIONS =====

  @doc """
  Sends a connection request from requester to recipient.

  If recipient already has a pending request to requester, both requests
  are automatically accepted.
  """
  def request_connection(requester, recipient) do
    requester_uuid = get_user_uuid(requester)
    recipient_uuid = get_user_uuid(recipient)

    cond do
      requester_uuid == recipient_uuid ->
        {:error, :self_connection}

      blocked?(requester_uuid, recipient_uuid) || blocked?(recipient_uuid, requester_uuid) ->
        {:error, :blocked}

      connected?(requester_uuid, recipient_uuid) ->
        {:error, :already_connected}

      true ->
        do_request_connection(requester_uuid, recipient_uuid)
    end
  end

  defp do_request_connection(requester_uuid, recipient_uuid) do
    case get_pending_request_between(recipient_uuid, requester_uuid) do
      %Connection{} = existing ->
        accept_connection_with_actor(existing, requester_uuid)

      nil ->
        case get_pending_request_between(requester_uuid, recipient_uuid) do
          %Connection{} -> {:error, :pending_request}
          nil -> create_pending_connection(requester_uuid, recipient_uuid)
        end
    end
  end

  @doc "Accepts a pending connection request."
  def accept_connection(%Connection{status: "pending"} = connection) do
    accept_connection_with_actor(connection, connection.recipient_uuid)
  end

  def accept_connection(%Connection{}), do: {:error, :not_pending}

  def accept_connection(connection_uuid) when is_binary(connection_uuid) do
    case repo().get(Connection, connection_uuid) do
      nil -> {:error, :not_found}
      connection -> accept_connection(connection)
    end
  end

  @doc "Rejects a pending connection request."
  def reject_connection(%Connection{status: "pending"} = connection) do
    repo().transaction(fn ->
      log_connection_history(
        connection.requester_uuid,
        connection.recipient_uuid,
        connection.recipient_uuid,
        "rejected"
      )

      case repo().delete(connection) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> repo().rollback(changeset)
      end
    end)
  end

  def reject_connection(%Connection{}), do: {:error, :not_pending}

  def reject_connection(connection_uuid) when is_binary(connection_uuid) do
    case repo().get(Connection, connection_uuid) do
      nil -> {:error, :not_found}
      connection -> reject_connection(connection)
    end
  end

  @doc "Cancels a pending outgoing connection request."
  def cancel_request(requester, connection_uuid) when is_binary(connection_uuid) do
    requester_uuid = get_user_uuid(requester)

    case repo().get(Connection, connection_uuid) do
      %Connection{requester_uuid: ^requester_uuid, status: "pending"} = connection ->
        do_cancel_request(connection, requester_uuid)

      %Connection{status: "pending"} ->
        {:error, :not_requester}

      %Connection{} ->
        {:error, :not_pending}

      nil ->
        {:error, :not_found}
    end
  end

  defp do_cancel_request(connection, actor_uuid) do
    repo().transaction(fn ->
      log_connection_history(
        connection.requester_uuid,
        connection.recipient_uuid,
        actor_uuid,
        "removed"
      )

      case repo().delete(connection) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> repo().rollback(changeset)
      end
    end)
  end

  @doc "Removes an existing connection between two users."
  def remove_connection(user_a, user_b) do
    user_a_uuid = get_user_uuid(user_a)
    user_b_uuid = get_user_uuid(user_b)

    case get_accepted_connection(user_a_uuid, user_b_uuid) do
      nil ->
        {:error, :not_connected}

      connection ->
        do_remove_connection(connection, user_a_uuid)
    end
  end

  defp do_remove_connection(connection, actor_uuid) do
    repo().transaction(fn ->
      log_connection_history(
        connection.requester_uuid,
        connection.recipient_uuid,
        actor_uuid,
        "removed"
      )

      case repo().delete(connection) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> repo().rollback(changeset)
      end
    end)
  end

  @doc "Checks if two users are connected (mutual connection exists)."
  def connected?(user_a, user_b) do
    user_a_uuid = get_user_uuid(user_a)
    user_b_uuid = get_user_uuid(user_b)

    Connection
    |> where([c], c.status == "accepted")
    |> where(
      [c],
      (c.requester_uuid == ^user_a_uuid and c.recipient_uuid == ^user_b_uuid) or
        (c.requester_uuid == ^user_b_uuid and c.recipient_uuid == ^user_a_uuid)
    )
    |> repo().exists?()
  end

  @doc "Returns all connections for a user."
  def list_connections(user, opts \\ []) do
    user_uuid = get_user_uuid(user)
    preload = Keyword.get(opts, :preload, true)

    query =
      Connection
      |> where([c], c.status == "accepted")
      |> where([c], c.requester_uuid == ^user_uuid or c.recipient_uuid == ^user_uuid)
      |> order_by([c], desc: c.responded_at)
      |> maybe_limit(opts[:limit])
      |> maybe_offset(opts[:offset])

    query = if preload, do: preload(query, [:requester, :recipient]), else: query

    repo().all(query)
  end

  @doc "Returns pending incoming connection requests for a user."
  def list_pending_requests(user, opts \\ []) do
    user_uuid = get_user_uuid(user)
    preload = Keyword.get(opts, :preload, true)

    query =
      Connection
      |> where([c], c.recipient_uuid == ^user_uuid and c.status == "pending")
      |> order_by([c], desc: c.requested_at)
      |> maybe_limit(opts[:limit])
      |> maybe_offset(opts[:offset])

    query = if preload, do: preload(query, [:requester]), else: query

    repo().all(query)
  end

  @doc "Returns pending outgoing connection requests sent by a user."
  def list_sent_requests(user, opts \\ []) do
    user_uuid = get_user_uuid(user)
    preload = Keyword.get(opts, :preload, true)

    query =
      Connection
      |> where([c], c.requester_uuid == ^user_uuid and c.status == "pending")
      |> order_by([c], desc: c.requested_at)
      |> maybe_limit(opts[:limit])
      |> maybe_offset(opts[:offset])

    query = if preload, do: preload(query, [:recipient]), else: query

    repo().all(query)
  end

  @doc "Returns the count of connections for a user."
  def connections_count(user) do
    user_uuid = get_user_uuid(user)

    Connection
    |> where([c], c.status == "accepted")
    |> where([c], c.requester_uuid == ^user_uuid or c.recipient_uuid == ^user_uuid)
    |> repo().aggregate(:count)
  end

  @doc "Returns the count of pending incoming connection requests for a user."
  def pending_requests_count(user) do
    user_uuid = get_user_uuid(user)

    Connection
    |> where([c], c.recipient_uuid == ^user_uuid and c.status == "pending")
    |> repo().aggregate(:count)
  end

  # ===== BLOCKS =====

  @doc "Blocks a user. Blocking removes any existing follows and connections."
  def block(blocker, blocked, reason \\ nil) do
    blocker_uuid = get_user_uuid(blocker)
    blocked_uuid = get_user_uuid(blocked)

    cond do
      blocker_uuid == blocked_uuid ->
        {:error, :self_block}

      blocked?(blocker_uuid, blocked_uuid) ->
        {:error, :already_blocked}

      true ->
        do_block(blocker_uuid, blocked_uuid, reason)
    end
  end

  defp do_block(blocker_uuid, blocked_uuid, reason) do
    repo().transaction(fn ->
      remove_follows_between_with_history(blocker_uuid, blocked_uuid)
      remove_connections_between_with_history(blocker_uuid, blocked_uuid)

      attrs = %{blocker_uuid: blocker_uuid, blocked_uuid: blocked_uuid, reason: reason}

      case %Block{} |> Block.changeset(attrs) |> repo().insert() do
        {:ok, block} ->
          log_block_history(blocker_uuid, blocked_uuid, "block", reason)
          block

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  @doc "Removes a block."
  def unblock(blocker, blocked) do
    blocker_uuid = get_user_uuid(blocker)
    blocked_uuid = get_user_uuid(blocked)

    case get_block(blocker_uuid, blocked_uuid) do
      nil -> {:error, :not_blocked}
      block -> do_unblock(block)
    end
  end

  defp do_unblock(block) do
    repo().transaction(fn ->
      case repo().delete(block) do
        {:ok, deleted} ->
          log_block_history(block.blocker_uuid, block.blocked_uuid, "unblock", nil)
          deleted

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  @doc "Checks if user A has blocked user B."
  def blocked?(blocker, blocked) do
    blocker_uuid = get_user_uuid(blocker)
    blocked_uuid = get_user_uuid(blocked)

    Block
    |> where([b], b.blocker_uuid == ^blocker_uuid and b.blocked_uuid == ^blocked_uuid)
    |> repo().exists?()
  end

  @doc "Checks if user is blocked by other user."
  def blocked_by?(user, other), do: blocked?(other, user)

  @doc "Returns all users blocked by a user."
  def list_blocked(user, opts \\ []) do
    user_uuid = get_user_uuid(user)
    preload = Keyword.get(opts, :preload, true)

    query =
      Block
      |> where([b], b.blocker_uuid == ^user_uuid)
      |> order_by([b], desc: b.inserted_at)
      |> maybe_limit(opts[:limit])
      |> maybe_offset(opts[:offset])

    query = if preload, do: preload(query, [:blocked]), else: query

    repo().all(query)
  end

  @doc "Returns the count of users blocked by a user."
  def blocked_count(user) do
    user_uuid = get_user_uuid(user)

    Block
    |> where([b], b.blocker_uuid == ^user_uuid)
    |> repo().aggregate(:count)
  end

  @doc "Checks if two users can interact (neither has blocked the other)."
  def can_interact?(user_a, user_b) do
    user_a_uuid = get_user_uuid(user_a)
    user_b_uuid = get_user_uuid(user_b)

    not (blocked?(user_a_uuid, user_b_uuid) or blocked?(user_b_uuid, user_a_uuid))
  end

  # ===== RELATIONSHIP STATUS =====

  @doc "Gets the full relationship status between two users in one call."
  def get_relationship(user_a, user_b) do
    user_a_uuid = get_user_uuid(user_a)
    user_b_uuid = get_user_uuid(user_b)

    # Batch follows check (1 query instead of 2)
    follows = get_follows_between(user_a_uuid, user_b_uuid)
    following = Enum.any?(follows, &(&1.follower_uuid == user_a_uuid))
    followed_by = Enum.any?(follows, &(&1.follower_uuid == user_b_uuid))

    # Batch connection check (1 query instead of 3)
    connection = get_any_connection_between(user_a_uuid, user_b_uuid)

    {connected, connection_pending} =
      case connection do
        %Connection{status: "accepted"} ->
          {true, nil}

        %Connection{status: "pending", requester_uuid: ^user_a_uuid} ->
          {false, :sent}

        %Connection{status: "pending"} ->
          {false, :received}

        _ ->
          {false, nil}
      end

    # Batch blocks check (1 query instead of 2)
    blocks = get_blocks_between(user_a_uuid, user_b_uuid)
    blocked = Enum.any?(blocks, &(&1.blocker_uuid == user_a_uuid))
    blocked_by = Enum.any?(blocks, &(&1.blocker_uuid == user_b_uuid))

    %{
      following: following,
      followed_by: followed_by,
      connected: connected,
      connection_pending: connection_pending,
      blocked: blocked,
      blocked_by: blocked_by
    }
  end

  # ===== PRIVATE HELPERS =====

  defp repo do
    PhoenixKit.RepoHelper.repo()
  end

  defp get_user_uuid(%{uuid: uuid}) when is_binary(uuid), do: uuid
  defp get_user_uuid(id) when is_binary(id), do: id

  defp get_follow(follower_uuid, followed_uuid) do
    Follow
    |> where([f], f.follower_uuid == ^follower_uuid and f.followed_uuid == ^followed_uuid)
    |> repo().one()
  end

  defp get_block(blocker_uuid, blocked_uuid) do
    Block
    |> where([b], b.blocker_uuid == ^blocker_uuid and b.blocked_uuid == ^blocked_uuid)
    |> repo().one()
  end

  defp get_pending_request_between(requester_uuid, recipient_uuid) do
    Connection
    |> where([c], c.requester_uuid == ^requester_uuid and c.recipient_uuid == ^recipient_uuid)
    |> where([c], c.status == "pending")
    |> repo().one()
  end

  defp get_accepted_connection(user_a_uuid, user_b_uuid) do
    Connection
    |> where([c], c.status == "accepted")
    |> where(
      [c],
      (c.requester_uuid == ^user_a_uuid and c.recipient_uuid == ^user_b_uuid) or
        (c.requester_uuid == ^user_b_uuid and c.recipient_uuid == ^user_a_uuid)
    )
    |> repo().one()
  end

  defp get_follows_between(user_a_uuid, user_b_uuid) do
    Follow
    |> where(
      [f],
      (f.follower_uuid == ^user_a_uuid and f.followed_uuid == ^user_b_uuid) or
        (f.follower_uuid == ^user_b_uuid and f.followed_uuid == ^user_a_uuid)
    )
    |> repo().all()
  end

  defp get_any_connection_between(user_a_uuid, user_b_uuid) do
    Connection
    |> where(
      [c],
      (c.requester_uuid == ^user_a_uuid and c.recipient_uuid == ^user_b_uuid) or
        (c.requester_uuid == ^user_b_uuid and c.recipient_uuid == ^user_a_uuid)
    )
    |> order_by(
      [c],
      fragment("CASE WHEN status = 'accepted' THEN 0 WHEN status = 'pending' THEN 1 ELSE 2 END")
    )
    |> limit(1)
    |> repo().one()
  end

  defp get_blocks_between(user_a_uuid, user_b_uuid) do
    Block
    |> where(
      [b],
      (b.blocker_uuid == ^user_a_uuid and b.blocked_uuid == ^user_b_uuid) or
        (b.blocker_uuid == ^user_b_uuid and b.blocked_uuid == ^user_a_uuid)
    )
    |> repo().all()
  end

  defp accept_connection_with_actor(%Connection{status: "pending"} = connection, actor_uuid) do
    repo().transaction(fn ->
      case connection
           |> Connection.status_changeset(%{status: "accepted"})
           |> repo().update() do
        {:ok, updated} ->
          log_connection_history(
            connection.requester_uuid,
            connection.recipient_uuid,
            actor_uuid,
            "accepted"
          )

          updated

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  defp accept_connection_with_actor(%Connection{}, _actor_uuid), do: {:error, :not_pending}

  defp create_pending_connection(requester_uuid, recipient_uuid) do
    repo().transaction(fn ->
      case %Connection{}
           |> Connection.changeset(%{
             requester_uuid: requester_uuid,
             recipient_uuid: recipient_uuid
           })
           |> repo().insert() do
        {:ok, connection} ->
          log_connection_history(requester_uuid, recipient_uuid, requester_uuid, "requested")
          connection

        {:error, changeset} ->
          repo().rollback(changeset)
      end
    end)
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset), do: offset(query, ^offset)

  defp get_total_follows_count do
    Follow |> repo().aggregate(:count)
  rescue
    Ecto.QueryError -> 0
    DBConnection.ConnectionError -> 0
  end

  defp get_total_connections_count do
    Connection |> where([c], c.status == "accepted") |> repo().aggregate(:count)
  rescue
    Ecto.QueryError -> 0
    DBConnection.ConnectionError -> 0
  end

  defp get_total_pending_count do
    Connection |> where([c], c.status == "pending") |> repo().aggregate(:count)
  rescue
    Ecto.QueryError -> 0
    DBConnection.ConnectionError -> 0
  end

  defp get_total_blocks_count do
    Block |> repo().aggregate(:count)
  rescue
    Ecto.QueryError -> 0
    DBConnection.ConnectionError -> 0
  end

  # ===== HISTORY LOGGING =====

  defp log_follow_history(follower_uuid, followed_uuid, action) do
    case %FollowHistory{}
         |> FollowHistory.changeset(%{
           follower_uuid: follower_uuid,
           followed_uuid: followed_uuid,
           action: action
         })
         |> repo().insert() do
      {:ok, _} -> :ok
      {:error, e} -> Logger.warning("Failed to log follow history: #{inspect(e)}")
    end
  end

  defp log_connection_history(user_a_uuid, user_b_uuid, actor_uuid, action) do
    case %ConnectionHistory{}
         |> ConnectionHistory.changeset(%{
           user_a_uuid: user_a_uuid,
           user_b_uuid: user_b_uuid,
           actor_uuid: actor_uuid,
           action: action
         })
         |> repo().insert() do
      {:ok, _} -> :ok
      {:error, e} -> Logger.warning("Failed to log connection history: #{inspect(e)}")
    end
  end

  defp log_block_history(blocker_uuid, blocked_uuid, action, reason) do
    case %BlockHistory{}
         |> BlockHistory.changeset(%{
           blocker_uuid: blocker_uuid,
           blocked_uuid: blocked_uuid,
           action: action,
           reason: reason
         })
         |> repo().insert() do
      {:ok, _} -> :ok
      {:error, e} -> Logger.warning("Failed to log block history: #{inspect(e)}")
    end
  end

  defp remove_follows_between_with_history(user_a_uuid, user_b_uuid) do
    follows =
      Follow
      |> where(
        [f],
        (f.follower_uuid == ^user_a_uuid and f.followed_uuid == ^user_b_uuid) or
          (f.follower_uuid == ^user_b_uuid and f.followed_uuid == ^user_a_uuid)
      )
      |> repo().all()

    Enum.each(follows, fn follow ->
      log_follow_history(follow.follower_uuid, follow.followed_uuid, "unfollow")
      repo().delete!(follow)
    end)
  end

  defp remove_connections_between_with_history(actor_uuid, user_b_uuid) do
    connections =
      Connection
      |> where(
        [c],
        (c.requester_uuid == ^actor_uuid and c.recipient_uuid == ^user_b_uuid) or
          (c.requester_uuid == ^user_b_uuid and c.recipient_uuid == ^actor_uuid)
      )
      |> repo().all()

    Enum.each(connections, fn connection ->
      log_connection_history(
        connection.requester_uuid,
        connection.recipient_uuid,
        actor_uuid,
        "removed"
      )

      repo().delete!(connection)
    end)
  end
end
