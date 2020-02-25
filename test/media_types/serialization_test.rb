require 'test_helper'

require 'abstract_controller/callbacks'
require 'abstract_controller/rendering'
require 'action_controller/metal'
require 'action_controller/metal/mime_responds'
require 'action_controller/metal/rendering'
require 'action_controller/metal/renderers'
require 'action_dispatch/http/request'
require 'action_dispatch/http/response'

require 'media_types'
require 'media_types/serialization/renderer/register'

require 'http_headers/accept'

require 'oj'

class MediaTypes::SerializationTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::MediaTypes::Serialization::VERSION
  end

  class MyResourceMediaType
    include ::MediaTypes::Dsl

    def self.organisation
      'mydomain'
    end

    use_name 'my_resource', defaults: { suffix: :json }

    validations do
      version 1 do
        attribute :name
        attribute :number, Numeric
        collection :items, allow_empty: true do
          attribute :label
          attribute :data, Object
        end

        attribute :source, optional: true
      end
    end
  end

  class MyResourceSerializer < ::MediaTypes::Serialization::Base
    validator MyResourceMediaType


    output version: 1 do |obj, version, context|
      attribute :name, obj[:title]
      attribute :number, obj[:count]
      attribute :items, obj[:data].map do |k, v|
        { label: k, data: v }
      end
    end

  end

  class BaseController < ActionController::Metal
    include AbstractController::Callbacks
    include AbstractController::Rendering
    include ActionController::MimeResponds
    include ActionController::Rendering
    include ActionController::Renderers

    include MediaTypes::Serialization
  end

  class FakeController < BaseController
    allow_output_serializer(MyResourceSerializer)

    def action
      input = request.body

      render_media input
    end
  end

  def setup
    @controller = FakeController.new
    @response = ActionDispatch::Response.new
  end

  def test_it_serializes_via_serializer
    content_type = MyResourceMediaType.version(1).identifier

    request = ActionDispatch::Request.new({
      Rack::RACK_INPUT => { title: 'test serialization', count: 1, data: {} },
      'HTTP_ACCEPT' => "#{content_type}, text/html; q=0.1"
    })

    @controller.dispatch(:action, request, @response)
    assert_equal content_type, @response.content_type.split(';').first

    result = Oj.load(@response.body)
    assert_equal( { "my_resource" => { "name" => "test serialization", "number" => 1, "items" => [] } }, result )
  end

  def test_it_only_serializes_what_it_knows
    content_type = 'text/html'
    request = ActionDispatch::Request.new({
      Rack::RACK_INPUT => { title: 'test serialization', count: 1, data: {} },
      'HTTP_ACCEPT' => "application/vnd.mydomain.nope, text/html; q=0.1"
    })

    MyResourceSerializer.define_method :to_html do |options = {}|
      "<code>#{to_hash.merge(source: 'to_html').to_json(options)}</code>"
    end

    @controller.dispatch(:action, request, @response)

    assert_equal content_type, @response.content_type.split(';').first
    assert_equal '<code>{"name":"test serialization","number":1,"items":[],"source":"to_html"}</code>', @response.body
  end

  def test_it_uses_the_html_wrapper
    request = ActionDispatch::Request.new({
      Rack::RACK_INPUT => { title: 'test serialization', count: 1, data: {} },
      'HTTP_ACCEPT' => "application/vnd.mydomain.nope, text/html; q=0.1"
    })

    assert_raises ActionView::MissingTemplate do
      @controller.dispatch(:action, request, @response)
    end
  end

  def test_it_uses_the_html_wrapper_for_the_api_viewer
    request = ActionDispatch::Request.new({
      Rack::RACK_INPUT => { title: 'test serialization', count: 1, data: {} },
      'HTTP_ACCEPT' => "application/vnd.xpbytes.api-viewer.v1"
    })

    # Define it to ensure this was not used
    MyResourceSerializer.define_method :to_html do |options = {}|
      "<code>#{to_hash.merge(source: 'to_html').to_json(options)}</code>"
    end

    assert_raises ActionView::MissingTemplate do
      @controller.dispatch(:action, request, @response)
    end
  end

  def test_it_extracts_links
    content_type = MyResourceMediaType.to_constructable.version(1).to_s
    Mime::Type.register(content_type, :my_special_symbol)

    request = ActionDispatch::Request.new({
      Rack::RACK_INPUT => { title: 'test serialization', count: 1, data: {} },
      'HTTP_ACCEPT' => "#{content_type}, text/html; q=0.1"
    })

    @controller.dispatch(:action, request, @response)
    assert_equal "<https://google.com>; rel=google; foo=bar", @response['Link']
  end
end

