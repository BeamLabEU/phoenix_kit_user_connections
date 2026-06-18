defmodule PhoenixKitUserConnections.Web.UserConnections do
  @moduledoc """
  User-facing LiveView for managing personal connections.
  """

  use PhoenixKitWeb, :live_view

  alias PhoenixKit.Settings
  alias PhoenixKit.Utils.Routes

  @tabs ~w(followers following connections requests blocked)
  @default_tab "connections"
  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    current_user = socket.assigns[:phoenix_kit_current_user]

    if current_user && PhoenixKitUserConnections.enabled?() do
      project_title = Settings.get_project_title()

      # Tab data is loaded in handle_params/3, which always runs after mount/3 for
      # a routed LiveView — loading it here as well would just be a wasted query.
      socket =
        socket
        |> assign(:page_title, "My Connections")
        |> assign(:page_subtitle, "Manage your followers, following, and connections")
        |> assign(:project_title, project_title)
        |> assign(:current_user, current_user)
        |> assign(:tab, @default_tab)
        |> load_counts()

      {:ok, socket}
    else
      message = if current_user, do: "Connections module is disabled", else: "Please log in"

      {:ok,
       socket
       |> put_flash(:error, message)
       |> push_navigate(to: Routes.path("/"))}
    end
  end

  @impl true
  def handle_params(%{"tab" => tab}, uri, socket) when tab in @tabs do
    socket =
      socket
      |> assign(:url_path, URI.parse(uri).path)
      |> assign(:tab, tab)
      |> load_tab_data(tab)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply,
     socket
     |> assign(:url_path, URI.parse(uri).path)
     |> assign(:tab, @default_tab)
     |> load_tab_data(@default_tab)}
  end

  @impl true
  def handle_event("unfollow", %{"uuid" => user_uuid}, socket) do
    case PhoenixKitUserConnections.unfollow(socket.assigns.current_user, user_uuid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Unfollowed successfully")
         |> load_counts()
         |> load_tab_data(socket.assigns.tab)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unfollow")}
    end
  end

  @impl true
  def handle_event("accept_request", %{"id" => connection_uuid}, socket) do
    case PhoenixKitUserConnections.accept_connection(connection_uuid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connection accepted!")
         |> load_counts()
         |> load_tab_data(socket.assigns.tab)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to accept request")}
    end
  end

  @impl true
  def handle_event("reject_request", %{"id" => connection_uuid}, socket) do
    case PhoenixKitUserConnections.reject_connection(connection_uuid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connection rejected")
         |> load_counts()
         |> load_tab_data(socket.assigns.tab)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to reject request")}
    end
  end

  @impl true
  def handle_event("remove_connection", %{"uuid" => user_uuid}, socket) do
    case PhoenixKitUserConnections.remove_connection(socket.assigns.current_user, user_uuid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connection removed")
         |> load_counts()
         |> load_tab_data(socket.assigns.tab)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove connection")}
    end
  end

  @impl true
  def handle_event("cancel_request", %{"id" => connection_uuid}, socket) do
    case PhoenixKitUserConnections.cancel_request(socket.assigns.current_user, connection_uuid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Request cancelled")
         |> load_counts()
         |> load_tab_data(socket.assigns.tab)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to cancel request")}
    end
  end

  @impl true
  def handle_event("unblock", %{"uuid" => user_uuid}, socket) do
    case PhoenixKitUserConnections.unblock(socket.assigns.current_user, user_uuid) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "User unblocked")
         |> load_counts()
         |> load_tab_data(socket.assigns.tab)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unblock user")}
    end
  end

  defp load_counts(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:followers_count, PhoenixKitUserConnections.followers_count(user))
    |> assign(:following_count, PhoenixKitUserConnections.following_count(user))
    |> assign(:connections_count, PhoenixKitUserConnections.connections_count(user))
    |> assign(:pending_count, PhoenixKitUserConnections.pending_requests_count(user))
    |> assign(:blocked_count, PhoenixKitUserConnections.blocked_count(user))
  end

  defp load_tab_data(socket, "followers") do
    user = socket.assigns.current_user
    assign(socket, :items, PhoenixKitUserConnections.list_followers(user, limit: @page_size))
  end

  defp load_tab_data(socket, "following") do
    user = socket.assigns.current_user
    assign(socket, :items, PhoenixKitUserConnections.list_following(user, limit: @page_size))
  end

  defp load_tab_data(socket, "connections") do
    user = socket.assigns.current_user
    assign(socket, :items, PhoenixKitUserConnections.list_connections(user, limit: @page_size))
  end

  defp load_tab_data(socket, "requests") do
    user = socket.assigns.current_user
    incoming = PhoenixKitUserConnections.list_pending_requests(user, limit: @page_size)
    outgoing = PhoenixKitUserConnections.list_sent_requests(user, limit: @page_size)

    socket
    |> assign(:incoming_requests, incoming)
    |> assign(:outgoing_requests, outgoing)
    |> assign(:items, [])
  end

  defp load_tab_data(socket, "blocked") do
    user = socket.assigns.current_user
    assign(socket, :items, PhoenixKitUserConnections.list_blocked(user, limit: @page_size))
  end

  defp load_tab_data(socket, _), do: assign(socket, :items, [])

  def get_other_user(connection, current_user_uuid) do
    if connection.requester_uuid == current_user_uuid do
      connection.recipient
    else
      connection.requester
    end
  end
end
