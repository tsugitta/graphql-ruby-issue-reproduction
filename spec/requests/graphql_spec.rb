require 'rails_helper'

RSpec.describe 'FragmentCache + Dataloader N+1 Investigation', type: :request do
  let(:users) { 5.times.map { |i| User.create!(name: "User #{i}") } }

  before do
    users.each do |user|
      2.times do |i|
        user.posts.create!(title: "Post #{i}")
      end
    end
  end

  let(:query) do
    <<~GRAPHQL
      query($useCache: Boolean!, $useDataloader: Boolean!) {
        users {
          id
          name
          posts(useCache: $useCache, useDataloader: $useDataloader) {
            id
            title
          }
        }
      }
    GRAPHQL
  end

  describe.skip 'N+1 for database' do
    context 'when cache_fragment is disabled' do
      it 'should have minimal query count with effective batching' do
        queries = []

        counter = ->(_name, _started, _finished, _unique_id, payload) do
          sql = payload[:sql].to_s
          if sql.start_with?("SELECT")
            queries << sql
          end
        end

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          post '/graphql', params: {
            query: query,
            variables: { useCache: false, useDataloader: false }.to_json
          }
        end

        puts "\n=== Queries without cache ==="
        queries.each.with_index(1) do |sql, i|
          puts "\n#{i}. #{sql}"
        end

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["errors"]).to be_nil
        expect(json_response["data"]["users"]).to be_present
        expect(queries.size).to be 2
      end
    end

    context 'when cache_fragment is enabled' do
      it 'should have minimal query count with effective batching' do
        GraphQL::FragmentCache.cache_store = ActiveSupport::Cache.lookup_store(:memory_store)

        queries = []

        counter = ->(_name, _started, _finished, _unique_id, payload) do
          sql = payload[:sql].to_s
          if sql.start_with?("SELECT")
            queries << sql
          end
        end


        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          post '/graphql', params: {
            query: query,
            variables: { useCache: true, useDataloader: true }.to_json
          }
        end

        puts "\n=== Queries with cache ==="
        queries.each.with_index(1) do |sql, i|
          puts "\n#{i}. #{sql}"
        end


        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["errors"]).to be_nil
        expect(json_response["data"]["users"]).to be_present
        expect(queries.size).to be 2
      end
    end
  end

  describe 'N+1 for cache' do
    class LoggingMemoryStore < ActiveSupport::Cache::MemoryStore
      attr_reader :read_multi_calls, :exist_calls

      def initialize
        super
        @read_multi_calls = []
        @exist_calls = []
      end

      def read_multi(*names)
        @read_multi_calls << names
        super
      end

      def exist?(name, options = nil)
        @exist_calls << name
        super
      end
    end

    let(:cache_store) { LoggingMemoryStore.new }

    before do
      GraphQL::FragmentCache.cache_store = cache_store
    end

    context 'without dataloader option' do
      it 'calls 1 read_multi' do
        post '/graphql', params: {
          query: query,
          variables: { useCache: true, useDataloader: false }.to_json
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["errors"]).to be_nil
        expect(json_response["data"]["users"]).to be_present

        expect(cache_store.read_multi_calls.size).to be 1
        expect(cache_store.exist_calls.size).to be 0

        puts "\n=== Cache operations without dataloader ==="
        puts "read_multi calls:"
        cache_store.read_multi_calls.each.with_index(1) do |names, i|
          puts "  #{i}. #{names.join(', ')}"
        end
        puts "exist? calls:"
        cache_store.exist_calls.each.with_index(1) do |name, i|
          puts "  #{i}. #{name}"
        end
      end
    end

    context 'with dataloader option' do
      it 'calls 1 read_multi and N exist?' do
        post '/graphql', params: {
          query: query,
          variables: { useCache: true, useDataloader: true }.to_json
        }

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["errors"]).to be_nil
        expect(json_response["data"]["users"]).to be_present

        expect(cache_store.read_multi_calls.size).to be 1
        expect(cache_store.exist_calls.size).to be users.size

        puts "\n=== Cache operations with dataloader ==="
        puts "read_multi calls:"
        cache_store.read_multi_calls.each.with_index(1) do |names, i|
          puts "  #{i}. #{names.join(', ')}"
        end
        puts "exist? calls:"
        cache_store.exist_calls.each.with_index(1) do |name, i|
          puts "  #{i}. #{name}"
        end
      end
    end
  end
end
