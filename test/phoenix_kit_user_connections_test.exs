defmodule PhoenixKitUserConnectionsTest do
  use ExUnit.Case

  # `function_exported?/3` answers FALSE for a module that is merely not
  # loaded yet, not only for one that lacks the function. Nothing forces
  # PhoenixKitUserConnections into memory before the three callback
  # assertions run, so under a random seed they failed intermittently --
  # roughly one run in four, and never when run alone, which is exactly the
  # shape that reads as "flaky infrastructure" and gets re-run instead of
  # fixed. Loading it once here makes them deterministic.
  setup_all do
    Code.ensure_loaded!(PhoenixKitUserConnections)
    :ok
  end

  describe "behaviour implementation" do
    test "implements PhoenixKit.Module" do
      behaviours =
        PhoenixKitUserConnections.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert PhoenixKit.Module in behaviours
    end

    test "has @phoenix_kit_module attribute for auto-discovery" do
      attrs = PhoenixKitUserConnections.__info__(:attributes)
      assert Keyword.get(attrs, :phoenix_kit_module) == [true]
    end
  end

  describe "required callbacks" do
    test "module_key/0 returns correct string" do
      assert PhoenixKitUserConnections.module_key() == "connections"
    end

    test "module_name/0 returns display name" do
      assert PhoenixKitUserConnections.module_name() == "Connections"
    end

    test "enabled?/0 returns a boolean" do
      assert is_boolean(PhoenixKitUserConnections.enabled?())
    end

    test "enable_system/0 is exported" do
      assert function_exported?(PhoenixKitUserConnections, :enable_system, 0)
    end

    test "disable_system/0 is exported" do
      assert function_exported?(PhoenixKitUserConnections, :disable_system, 0)
    end
  end

  describe "permission_metadata/0" do
    test "returns a map with required fields" do
      meta = PhoenixKitUserConnections.permission_metadata()
      assert %{key: key, label: label, icon: icon, description: desc} = meta
      assert is_binary(key)
      assert is_binary(label)
      assert is_binary(icon)
      assert is_binary(desc)
    end

    test "key matches module_key" do
      meta = PhoenixKitUserConnections.permission_metadata()
      assert meta.key == PhoenixKitUserConnections.module_key()
    end

    test "icon uses hero- prefix" do
      meta = PhoenixKitUserConnections.permission_metadata()
      assert String.starts_with?(meta.icon, "hero-")
    end
  end

  describe "admin_tabs/0" do
    test "returns a non-empty list" do
      tabs = PhoenixKitUserConnections.admin_tabs()
      assert [_ | _] = tabs
    end

    test "main tab has required fields" do
      [tab | _] = PhoenixKitUserConnections.admin_tabs()
      assert tab.id == :admin_connections
      assert tab.label == "Connections"
      assert tab.level == :admin
      assert tab.permission == PhoenixKitUserConnections.module_key()
      assert tab.group == :admin_modules
    end

    test "main tab has live_view for route generation" do
      [tab | _] = PhoenixKitUserConnections.admin_tabs()
      assert {PhoenixKitUserConnections.Web.Connections, :index} = tab.live_view
    end
  end

  describe "version/0" do
    test "matches the version in mix.exs" do
      assert PhoenixKitUserConnections.version() == Mix.Project.config()[:version]
    end
  end

  describe "optional callbacks" do
    test "get_config/0 is exported" do
      assert function_exported?(PhoenixKitUserConnections, :get_config, 0)
    end

    test "css_sources/0 returns list with app name" do
      assert PhoenixKitUserConnections.css_sources() == [:phoenix_kit_user_connections]
    end
  end

  describe "Block.changeset/2 reason length" do
    # The column is `character varying(255)`. A changeset that allowed more
    # accepted the value and then raised Postgrex.Error on insert, handing the
    # caller a crash where it had asked for a changeset error.
    test "accepts a reason at the column's limit" do
      attrs = %{
        blocker_uuid: UUIDv7.generate(),
        blocked_uuid: UUIDv7.generate(),
        reason: String.duplicate("a", 255)
      }

      assert %Ecto.Changeset{valid?: true} =
               PhoenixKitUserConnections.Block.changeset(
                 %PhoenixKitUserConnections.Block{},
                 attrs
               )
    end

    # Postgres counts CHARACTERS; Ecto's validate_length counts GRAPHEME
    # CLUSTERS by default. 255 decomposed graphemes are 510 codepoints, which
    # a plain `max: 255` accepts and `character varying(255)` refuses with
    # :string_data_right_truncation — the same crash, reachable with nothing
    # more exotic than an accented reason. Hence `count: :codepoints`.
    test "counts codepoints, not graphemes, so a decomposed reason is refused" do
      decomposed = String.duplicate("e\u0301", 255)

      assert String.length(decomposed) == 255
      assert length(String.to_charlist(decomposed)) == 510

      attrs = %{
        blocker_uuid: UUIDv7.generate(),
        blocked_uuid: UUIDv7.generate(),
        reason: decomposed
      }

      assert %Ecto.Changeset{valid?: false} =
               PhoenixKitUserConnections.Block.changeset(
                 %PhoenixKitUserConnections.Block{},
                 attrs
               )
    end

    test "rejects a reason past it rather than deferring to the database" do
      attrs = %{
        blocker_uuid: UUIDv7.generate(),
        blocked_uuid: UUIDv7.generate(),
        reason: String.duplicate("a", 256)
      }

      changeset =
        PhoenixKitUserConnections.Block.changeset(
          %PhoenixKitUserConnections.Block{},
          attrs
        )

      refute changeset.valid?
      assert changeset.errors[:reason]
    end
  end
end
