require 'rails_helper'

RSpec.describe 'FragmentCache + Dataloader N+1 Investigation', type: :request do
  before do
    user1 = User.create!(name: "Alice")
    user2 = User.create!(name: "Bob")
    5.times do |i|
      user1.posts.create!(title: "Alice Post #{i}")
      user2.posts.create!(title: "Bob Post #{i}")
    end
  end

  let(:query) do
    <<~GRAPHQL
      query($useCache: Boolean!) {
        users {
          id
          name
          posts(useCache: $useCache) {
            id
            title
          }
        }
      }
    GRAPHQL
  end

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
          variables: { useCache: false }.to_json
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
          variables: { useCache: true }.to_json
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
