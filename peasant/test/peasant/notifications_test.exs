defmodule Peasant.NotificationsTest do
  use Peasant.GeneralCase

  alias Peasant.Notifications, as: N

  @pubsub Peasant.PubSub

  setup do
    topic = "#{Faker.Lorem.word()}:#{Faker.Lorem.word()}"

    message = %{
      event_id: Faker.Lorem.word(),
      tool_uuid: UUID.uuid4()
    }

    N.subscribe(topic)

    [topic: topic, message: message]
  end

  describe "subscribe/1" do
    @describetag :integration

    test "shoud subscribe current process to given topic messages", %{
      topic: topic,
      message: message
    } do
      Phoenix.PubSub.broadcast(@pubsub, topic, message)

      assert_receive ^message
    end
  end

  describe "broadcast/1" do
    @describetag :integration

    test "shoud broadcast a message to a given topic", %{
      topic: topic,
      message: message
    } do
      N.broadcast(topic, message)

      assert_receive ^message
    end
  end
end
