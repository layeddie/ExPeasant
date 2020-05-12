defmodule PeasantWeb.ToolsLive do
  use PeasantWeb, :live_view

  import PeasantWeb.ToolsHelpers

  import PeasantWeb.TableHelpers
  import PeasantWeb.LiveHelpers

  alias Peasant.Tool.Event, as: Tool

  @tools Peasant.Tool.domain()

  @sort_by ~w(name attached placement __struct__ updated_at)

  @attached_color %{
    true => "green",
    false => "dark-gray"
  }

  @impl true
  def mount(_params, _session, socket) do
    socket =
      Phoenix.LiveView.assign(socket, :menu, %{
        action: socket.assigns.live_action
      })

    Peasant.subscribe(@tools)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {
      :noreply,
      socket
      |> apply_action(params)
    }
  end

  defp apply_action(socket, %{"id" => uuid} = _params),
    do: fetch_tool(socket, uuid)

  defp apply_action(socket, params),
    do:
      assign(
        socket,
        tool: nil,
        changeset: nil,
        uuid: nil
      )
      |> assign_params(params, @sort_by)
      |> fetch_tools()
      |> set_page_title()

  defp fetch_tool(socket, uuid) do
    assign(
      socket,
      tool: get_tool(uuid),
      uuid: uuid
    )
    |> set_page_title()
  end

  defp fetch_tools(socket) do
    %{
      search: search,
      sort_by: sort_by,
      sort_dir: sort_dir,
      limit: limit,
      offset: offset
    } = socket.assigns.params

    {tools, total} = list_tools(search, sort_by, sort_dir, limit, offset)

    assign(socket, tools: tools, total: total)
  end

  @impl true
  def handle_info(%Tool.Registered{}, socket),
    do: {:noreply, fetch_tools(socket)}

  def handle_info(%Tool.Attached{tool_uuid: uuid}, socket) do
    tools =
      socket.assigns.tools
      |> update_tool(uuid, &%{&1 | attached: true})

    {:noreply, assign(socket, tools: tools)}
  end

  def handle_info(:refresh, socket) do
    {:noreply, fetch_tools(socket)}
  end

  @impl true
  def handle_event("select_limit", %{"limit" => limit}, socket) do
    %{params: params} = socket.assigns
    {:noreply, push_patch(socket, to: self_path(socket, %{params | limit: limit}))}
  end

  # @impl true
  # def handle_event("suggest", %{"q" => query}, socket) do
  #   {:noreply, assign(socket, results: search(query), query: query)}
  # end

  # @impl true
  # def handle_event("search", %{"q" => query}, socket) do
  #   case search(query) do
  #     %{^query => vsn} ->
  #       {:noreply, redirect(socket, external: "https://hexdocs.pm/#{query}/#{vsn}")}

  #     _ ->
  #       {:noreply,
  #        socket
  #        |> put_flash(:error, "No dependencies found matching \"#{query}\"")
  #        |> assign(results: %{}, query: query)}
  #   end
  # end

  # defp search(query) do
  #   if not PeasantWeb.Endpoint.config(:code_reloader) do
  #     raise "action disabled when not in development"
  #   end

  #   for {app, desc, vsn} <- Application.started_applications(),
  #       app = to_string(app),
  #       String.starts_with?(app, query) and not List.starts_with?(desc, ~c"ERTS"),
  #       into: %{},
  #       do: {app, vsn}
  # end

  defp self_path(socket, params) do
    live_peasant_path(socket, :tools, [], params)
  end

  defp attached_color(state), do: @attached_color[state]

  defp update_tool(tools, uuid, fun) do
    case Enum.find_index(tools, &(&1.uuid == uuid)) do
      nil -> tools
      index -> List.update_at(tools, index, fun)
    end
  end

  defp set_page_title(socket) do
    title =
      cond do
        socket.assigns.tool && socket.assigns.tool.new -> "New tool"
        socket.assigns.tool -> socket.assigns.tool.name
        true -> "Tools"
      end

    assign(socket, page_title: title)
  end
end
