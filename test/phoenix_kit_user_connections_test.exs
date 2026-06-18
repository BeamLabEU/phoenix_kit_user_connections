defmodule PhoenixKitUserConnectionsTest do
  use ExUnit.Case

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
    test "returns a version string" do
      assert PhoenixKitUserConnections.version() == "0.1.2"
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
end
