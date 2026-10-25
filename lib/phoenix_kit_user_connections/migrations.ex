defmodule PhoenixKitUserConnections.Migrations do
  @moduledoc """
  Module-owned versioned migrations for `phoenix_kit_user_connections` — the protocol
  core's `mix phoenix_kit.update` discovers through `migration_module/0`:
  `current_version/0`, `migrated_version_runtime/1`, an idempotent `up/1` and a
  version-aware `down/1`. Same shape as `phoenix_kit_locations`' chain.

  ## What V1 is

  An ADOPTION step for the six tables core's chain creates for this module:
  `phoenix_kit_user_follows`, `phoenix_kit_user_follows_history`, `phoenix_kit_user_connections`, `phoenix_kit_user_connections_history`, `phoenix_kit_user_blocks` and `phoenix_kit_user_blocks_history`. Their shape is core's V135 baseline plus V188, the three unique indexes (one follow per pair, one block per pair, one connection per requester and recipient) that V188 creates after removing duplicate rows. The statements below re-state what a fresh core install builds today, with core's exact object names. V188 is why the package requires core 2.22.3 or later: on an older core, V1's unique indexes would meet those duplicates and fail.

    * On every existing install the tables are already there: each `CREATE
      TABLE IF NOT EXISTS`, guarded `DO $$ … pg_constraint … $$` block and
      `CREATE INDEX IF NOT EXISTS` finds its target and does nothing. The only
      new object is the `pkucn_schema:1` marker.
    * On an install whose core no longer creates the tables, the same
      statements create them, identical to what core built.
      `test/integration/migrations_build_alone_test.exs` proves that against
      core's chain (core's `PhoenixKit.TestSupport.ModuleChainCheck`).

  From V1 on, this chain owns the tables' shape: a change to them is a new
  version here, never a core migration (core enforces that since V223; see
  core's `dev_docs/plans/2026-10-25-module-table-ownership.md`). Until core's
  `ExpectedSchema` manifest hands these tables over, a version that reshapes an
  object the manifest declares must first take it out of the manifest, or
  `mix phoenix_kit.repair` restores the old shape; a version that only adds
  objects the manifest never names needs no core step.

  ## What `down/1` is NOT

  `down/1` rewrites the version marker; it never drops a table. The rows are
  people's follows, connections and blocks with their history, and on every
  current install core created the tables.
  `test/phoenix_kit_user_connections/migrations_test.exs` pins this by asserting that no
  statement this module can emit matches `DROP`, `TRUNCATE` or `DELETE`.

  ## Adding a version

  1. Append the new statements to `up_statements/2` behind `target >= N`
     (never edit V1's statements: hosts past V1 never re-run them).
  2. Bump `@current_version`.

  The migrated version is a `pkucn_schema:<N>` `COMMENT ON TABLE` marker on
  `phoenix_kit_user_connections`; a table without one reads as version 0 — the shape
  core built before this chain existed.
  """

  use Ecto.Migration

  @current_version 1
  @marker_prefix "pkucn_schema:"
  @version_table "phoenix_kit_user_connections"

  @spec current_version() :: pos_integer()
  def current_version, do: @current_version

  @doc "The table carrying the `pkucn_schema:<N>` marker (auditor contract)."
  @spec version_table() :: String.t()
  def version_table, do: @version_table

  @doc "The chain version read from INSIDE a migration (migration repo)."
  def migrated_version(opts \\ []) do
    prefix = validated_prefix(opts)
    %{rows: rows} = repo().query!(marker_query(), [prefix])
    rows |> List.first() |> marker_to_version()
  end

  @doc """
  The chain version currently applied in the database, read OUTSIDE a
  migration (the protocol shape core's update task calls — `opts` with
  `:prefix`): the `pkucn_schema:<N>` marker when present; a marker-less table
  reads as `0` (core's shape — V1 is purely adoptive, there is no pre-chain
  content to defend).

  `catch :exit` matters as much as `rescue`: a dead or unstarted pool exits
  rather than raising, and `mix phoenix_kit.status` calls this across every
  installed module.
  """
  def migrated_version_runtime(opts \\ []) do
    prefix = validated_prefix(opts)

    case PhoenixKit.RepoHelper.repo().query(marker_query(), [prefix]) do
      {:ok, %{rows: rows}} -> rows |> List.first() |> marker_to_version()
      _ -> 0
    end
  rescue
    # An invalid prefix must surface as the validation error, not be
    # swallowed into 0 ("not installed").
    e in ArgumentError -> reraise e, __STACKTRACE__
    _ -> 0
  catch
    :exit, _ -> 0
  end

  @doc "Applies every chain version up to `target` (`:version` in `opts`, default `current_version/0`); idempotent."
  def up(opts \\ []) do
    prefix = validated_prefix(opts)

    target =
      if is_list(opts), do: Keyword.get(opts, :version, @current_version), else: @current_version

    prefix
    |> up_statements(target)
    |> Enum.each(&execute/1)
  end

  @doc "Rolls back to `target` (`:version` in `opts`). Never drops a table — see the moduledoc."
  def down(opts \\ []) do
    prefix = validated_prefix(opts)
    target = if is_list(opts), do: Keyword.get(opts, :version, 0), else: 0

    prefix
    |> down_statements(target)
    |> Enum.each(&execute/1)
  end

  @doc """
  The SQL `up/1` executes, as data — the testable single source. Every
  statement is idempotent (`IF NOT EXISTS` / guarded `DO $$` block /
  `COMMENT`), so it is safe to replay on an install where core already created
  the tables and on one with none of them.

  V1 order: every `CREATE TABLE`, then every constraint guard (primary keys,
  then foreign keys), then every index, then the version marker last.

  `target` selects how much of the chain to emit (default `current_version/0`);
  the wrapper migration core's update task generates passes an explicit
  `:version`, and a stale wrapper asking for an older version must not receive
  a newer version's objects.
  """
  @spec up_statements(String.t(), pos_integer()) :: [String.t()]
  def up_statements(prefix \\ "public", target \\ @current_version)

  def up_statements(prefix, target) when is_integer(target) and target >= 1 do
    prefix = validated_prefix(prefix: prefix)
    p = "#{prefix}."
    target = min(target, @current_version)

    List.flatten([
      v1_statements(prefix, p),
      "COMMENT ON TABLE #{p}#{@version_table} IS '#{@marker_prefix}#{target}'"
    ])
  end

  @doc "The SQL `down/1` executes, as data (marker bookkeeping only)."
  @spec down_statements(String.t(), non_neg_integer()) :: [String.t()]
  def down_statements(prefix \\ "public", target \\ 0)
      when is_integer(target) and target >= 0 do
    prefix = validated_prefix(prefix: prefix)
    p = "#{prefix}."

    if target > 0 do
      ["COMMENT ON TABLE #{p}#{@version_table} IS '#{@marker_prefix}#{target}'"]
    else
      ["COMMENT ON TABLE #{p}#{@version_table} IS NULL"]
    end
  end

  # ── V1: adoption of the tables core's chain creates ─────────────────────

  defp v1_statements(prefix, p) do
    [tables(p), constraints(prefix, p), indexes(p)]
  end

  # Columns, types, defaults and order as a fresh core install builds them.
  defp tables(p) do
    [
      """
      CREATE TABLE IF NOT EXISTS #{p}phoenix_kit_user_follows (
        "uuid" uuid DEFAULT #{p}uuid_generate_v7() NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "follower_uuid" uuid NOT NULL,
        "followed_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{p}phoenix_kit_user_follows_history (
        "uuid" uuid DEFAULT #{p}uuid_generate_v7() NOT NULL,
        "action" character varying(255) NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "follower_uuid" uuid NOT NULL,
        "followed_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{p}phoenix_kit_user_connections (
        "uuid" uuid DEFAULT #{p}uuid_generate_v7() NOT NULL,
        "status" character varying(255) DEFAULT 'pending'::character varying NOT NULL,
        "requested_at" timestamp with time zone NOT NULL,
        "responded_at" timestamp with time zone,
        "inserted_at" timestamp with time zone NOT NULL,
        "updated_at" timestamp with time zone NOT NULL,
        "requester_uuid" uuid NOT NULL,
        "recipient_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{p}phoenix_kit_user_connections_history (
        "uuid" uuid DEFAULT #{p}uuid_generate_v7() NOT NULL,
        "action" character varying(255) NOT NULL,
        "inserted_at" timestamp with time zone NOT NULL,
        "user_a_uuid" uuid NOT NULL,
        "user_b_uuid" uuid NOT NULL,
        "actor_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{p}phoenix_kit_user_blocks (
        "uuid" uuid DEFAULT #{p}uuid_generate_v7() NOT NULL,
        "reason" character varying(255),
        "inserted_at" timestamp with time zone NOT NULL,
        "blocker_uuid" uuid NOT NULL,
        "blocked_uuid" uuid NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS #{p}phoenix_kit_user_blocks_history (
        "uuid" uuid DEFAULT #{p}uuid_generate_v7() NOT NULL,
        "action" character varying(255) NOT NULL,
        "reason" character varying(255),
        "inserted_at" timestamp with time zone NOT NULL,
        "blocker_uuid" uuid NOT NULL,
        "blocked_uuid" uuid NOT NULL
      )
      """
    ]
  end

  # Core's constraint names, from its V135 baseline.
  defp constraints(prefix, p) do
    [
      guarded_constraint(
        prefix,
        "phoenix_kit_user_follows",
        "phoenix_kit_user_follows_pkey",
        "ALTER TABLE #{p}phoenix_kit_user_follows ADD CONSTRAINT phoenix_kit_user_follows_pkey PRIMARY KEY (uuid)"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_follows_history",
        "phoenix_kit_user_follows_history_pkey",
        "ALTER TABLE #{p}phoenix_kit_user_follows_history ADD CONSTRAINT phoenix_kit_user_follows_history_pkey PRIMARY KEY (uuid)"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_connections",
        "phoenix_kit_user_connections_pkey",
        "ALTER TABLE #{p}phoenix_kit_user_connections ADD CONSTRAINT phoenix_kit_user_connections_pkey PRIMARY KEY (uuid)"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_connections_history",
        "phoenix_kit_user_connections_history_pkey",
        "ALTER TABLE #{p}phoenix_kit_user_connections_history ADD CONSTRAINT phoenix_kit_user_connections_history_pkey PRIMARY KEY (uuid)"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_blocks",
        "phoenix_kit_user_blocks_pkey",
        "ALTER TABLE #{p}phoenix_kit_user_blocks ADD CONSTRAINT phoenix_kit_user_blocks_pkey PRIMARY KEY (uuid)"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_blocks_history",
        "phoenix_kit_user_blocks_history_pkey",
        "ALTER TABLE #{p}phoenix_kit_user_blocks_history ADD CONSTRAINT phoenix_kit_user_blocks_history_pkey PRIMARY KEY (uuid)"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_follows",
        "fk_user_follows_followed_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_follows ADD CONSTRAINT fk_user_follows_followed_uuid FOREIGN KEY (followed_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_follows",
        "fk_user_follows_follower_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_follows ADD CONSTRAINT fk_user_follows_follower_uuid FOREIGN KEY (follower_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_follows_history",
        "fk_user_follows_history_followed_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_follows_history ADD CONSTRAINT fk_user_follows_history_followed_uuid FOREIGN KEY (followed_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_follows_history",
        "fk_user_follows_history_follower_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_follows_history ADD CONSTRAINT fk_user_follows_history_follower_uuid FOREIGN KEY (follower_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_connections",
        "fk_user_connections_recipient_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_connections ADD CONSTRAINT fk_user_connections_recipient_uuid FOREIGN KEY (recipient_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_connections",
        "fk_user_connections_requester_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_connections ADD CONSTRAINT fk_user_connections_requester_uuid FOREIGN KEY (requester_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_connections_history",
        "fk_user_connections_history_actor_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_connections_history ADD CONSTRAINT fk_user_connections_history_actor_uuid FOREIGN KEY (actor_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_connections_history",
        "fk_user_connections_history_user_a_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_connections_history ADD CONSTRAINT fk_user_connections_history_user_a_uuid FOREIGN KEY (user_a_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_connections_history",
        "fk_user_connections_history_user_b_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_connections_history ADD CONSTRAINT fk_user_connections_history_user_b_uuid FOREIGN KEY (user_b_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_blocks",
        "fk_user_blocks_blocked_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_blocks ADD CONSTRAINT fk_user_blocks_blocked_uuid FOREIGN KEY (blocked_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_blocks",
        "fk_user_blocks_blocker_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_blocks ADD CONSTRAINT fk_user_blocks_blocker_uuid FOREIGN KEY (blocker_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_blocks_history",
        "fk_user_blocks_history_blocked_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_blocks_history ADD CONSTRAINT fk_user_blocks_history_blocked_uuid FOREIGN KEY (blocked_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      ),
      guarded_constraint(
        prefix,
        "phoenix_kit_user_blocks_history",
        "fk_user_blocks_history_blocker_uuid",
        "ALTER TABLE #{p}phoenix_kit_user_blocks_history ADD CONSTRAINT fk_user_blocks_history_blocker_uuid FOREIGN KEY (blocker_uuid) REFERENCES #{p}phoenix_kit_users(uuid) ON DELETE CASCADE"
      )
    ]
  end

  # Index names are core's. They stay bare on CREATE (an index lives in its
  # table's schema).
  defp indexes(p) do
    [
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_follows_followed_uuid_idx ON #{p}phoenix_kit_user_follows USING btree (followed_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_follows_follower_uuid_idx ON #{p}phoenix_kit_user_follows USING btree (follower_uuid)",
      "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_user_follows_unique_idx ON #{p}phoenix_kit_user_follows USING btree (follower_uuid, followed_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_follows_history_followed_uuid_idx ON #{p}phoenix_kit_user_follows_history USING btree (followed_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_follows_history_follower_uuid_idx ON #{p}phoenix_kit_user_follows_history USING btree (follower_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_follows_history_inserted_at_index ON #{p}phoenix_kit_user_follows_history USING btree (inserted_at)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_connections_recipient_uuid_idx ON #{p}phoenix_kit_user_connections USING btree (recipient_uuid)",
      "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_user_connections_requester_recipient_uidx ON #{p}phoenix_kit_user_connections USING btree (LEAST(requester_uuid, recipient_uuid), GREATEST(requester_uuid, recipient_uuid))",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_connections_requester_uuid_idx ON #{p}phoenix_kit_user_connections USING btree (requester_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_connections_status_index ON #{p}phoenix_kit_user_connections USING btree (status)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_connections_history_actor_uuid_idx ON #{p}phoenix_kit_user_connections_history USING btree (actor_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_connections_history_inserted_at_index ON #{p}phoenix_kit_user_connections_history USING btree (inserted_at)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_connections_history_user_a_uuid_idx ON #{p}phoenix_kit_user_connections_history USING btree (user_a_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_connections_history_user_b_uuid_idx ON #{p}phoenix_kit_user_connections_history USING btree (user_b_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_blocks_blocked_uuid_idx ON #{p}phoenix_kit_user_blocks USING btree (blocked_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_blocks_blocker_uuid_idx ON #{p}phoenix_kit_user_blocks USING btree (blocker_uuid)",
      "CREATE UNIQUE INDEX IF NOT EXISTS phoenix_kit_user_blocks_unique_idx ON #{p}phoenix_kit_user_blocks USING btree (blocker_uuid, blocked_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_blocks_history_blocked_uuid_idx ON #{p}phoenix_kit_user_blocks_history USING btree (blocked_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_blocks_history_blocker_uuid_idx ON #{p}phoenix_kit_user_blocks_history USING btree (blocker_uuid)",
      "CREATE INDEX IF NOT EXISTS phoenix_kit_user_blocks_history_inserted_at_index ON #{p}phoenix_kit_user_blocks_history USING btree (inserted_at)"
    ]
  end

  defp guarded_constraint(prefix, table, constraint_name, add_sql) do
    """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE c.conname = '#{constraint_name}'
          AND t.relname = '#{table}'
          AND n.nspname = '#{prefix}'
      ) THEN
        #{add_sql};
      END IF;
    END
    $$
    """
  end

  defp marker_query do
    """
    SELECT d.description
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_description d
      ON d.objoid = c.oid AND d.objsubid = 0 AND d.classoid = 'pg_class'::regclass
    WHERE n.nspname = $1 AND c.relname = '#{@version_table}' AND c.relkind = 'r'
    """
  end

  defp marker_to_version([@marker_prefix <> n]) do
    case Integer.parse(n) do
      {v, ""} when v >= 0 -> v
      _ -> 0
    end
  end

  defp marker_to_version(_), do: 0

  defp validated_prefix(opts) do
    prefix =
      case opts do
        opts when is_list(opts) -> Keyword.get(opts, :prefix) || "public"
        %{prefix: prefix} when is_binary(prefix) -> prefix
        _ -> "public"
      end

    # Interpolated into DDL and into the guard blocks' string literals.
    unless prefix =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ do
      raise ArgumentError, "invalid schema prefix: #{inspect(prefix)}"
    end

    prefix
  end
end
