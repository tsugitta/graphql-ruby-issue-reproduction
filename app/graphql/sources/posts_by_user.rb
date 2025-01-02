# frozen_string_literal: true

module Sources
  class PostsByUser < GraphQL::Dataloader::Source
    def fetch(user_ids)
      posts = Post.where(user_id: user_ids).group_by(&:user_id)
      user_ids.map { |uid| posts[uid] || [] }
    end
  end
end
