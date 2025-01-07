# frozen_string_literal: true

module Types
  class UserType < Types::BaseObject
    field :id, ID, null: false
    field :name, String

    field :posts, [ Types::PostType ], null: false do
      argument :use_cache, Boolean, required: true
      argument :use_dataloader, Boolean, required: true
    end
    def posts(use_cache:, use_dataloader:)
      if use_cache
        cache_fragment(expires_in: 1.minute, dataloader: use_dataloader) do
          dataloader.with(Sources::PostsByUser).load(object.id)
        end
      else
        dataloader.with(Sources::PostsByUser).load(object.id)
      end
    end
  end
end
