require 'spec_helper'

describe PgMorph::Adapter do
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do
    include PgMorph::Adapter
    
    def run(query)
      ActiveRecord::Base.connection.select_value(query)
    end
  end

  let(:comment) { Comment.create(content: 'comment') }

  before do
    @adapter = ActiveRecord::Base.connection
    @comments_polymorphic = PgMorph::Polymorphic.new(:likes, :comments, column: :likeable)
    @posts_polymorphic = PgMorph::Polymorphic.new(:likes, :posts, column: :likeable)
  end

  describe '#add_polymorphic_foreign_key' do
    it 'creates proxy table' do
      @adapter.add_polymorphic_foreign_key(:likes, :comments, column: :likeable)
      expect(@adapter.run 'SELECT id FROM likes_comments')
        .to be_nil
    end
  end

  describe '#remove_polymorphic_foreign_key' do
    it 'removes proxy table' do
      @adapter.add_polymorphic_foreign_key(:likes, :comments, column: :likeable)
      expect(@adapter.run 'SELECT id FROM likes_comments').to be_nil

      @adapter.remove_polymorphic_foreign_key(:likes, :comments, column: :likeable)
      expect { @adapter.run 'SELECT id FROM likes_comments' }
        .to raise_error ActiveRecord::StatementInvalid
    end

    it 'prevents from removing partition with data' do
      @adapter.add_polymorphic_foreign_key(:likes, :comments, column: :likeable)
      Like.create(likeable: comment)

      expect { @adapter.remove_polymorphic_foreign_key(:likes, :comments, column: :likeable) }
        .to raise_error PG::Error
    end
  end

  describe 'operations on a partition' do
    let(:comment) { Comment.create(content: 'comment') }
    let(:post) { Post.create(content: 'content') }

    before do
      @adapter.add_polymorphic_foreign_key(:likes, :comments, column: :likeable)
      @comment_like = Like.create(likeable: comment)
    end

    context "creating records" do
      it "works with single partition" do
        expect(Like.count).to eq(1)
        expect(@comment_like.id).to eq Like.last.id
      end

      it "works with multiple partitions" do
        @adapter.add_polymorphic_foreign_key(:likes, :posts, column: :likeable)
        post_like = Like.create(likeable: post)

        expect(Like.count).to eq 2
        expect(post_like.id).to eq Like.last.id
      end

      it "raises error for a missing partition" do
        expect { Like.create(likeable: post) }
          .to raise_error ActiveRecord::StatementInvalid
      end

      it "works if no partitions" do
        @comment_like.destroy
        expect(Like.count).to eq 0
        @adapter.remove_polymorphic_foreign_key(:likes, :comments, column: :likeable)
        like = Like.create(likeable: post)

        expect(Like.count).to eq 1
        expect(like.id).to eq Like.last.id
      end
    end

    context "updating records" do
      let(:another_comment) { Comment.create(content: 'comment') }

      before do
        @adapter.add_polymorphic_foreign_key(:likes, :posts, column: :likeable)
      end

      it 'works within one partition' do
        expect(@comment_like.likeable).to eq(comment)

        @comment_like.likeable = another_comment
        @comment_like.save

        @comment_like.reload
        expect(@comment_like.likeable).to eq(another_comment)
      end

      it 'does not allow to change associated type' do
        expect(@comment_like.likeable).to eq(comment)

        @comment_like.likeable = post
        expect { @comment_like.save }
          .to raise_error ActiveRecord::StatementInvalid
      end
    end

    context "deleting records" do
      before do
        expect(@adapter.run "SELECT id FROM likes WHERE id = #{@comment_like.id}")
          .to eq @comment_like.id.to_s
        
        expect(@adapter.run "SELECT id FROM likes_comments WHERE id = #{@comment_like.id}")
          .to eq @comment_like.id.to_s
        
        @comment_like.destroy
      end

      it "works on a partition" do
        expect(@adapter.run "SELECT id FROM likes WHERE id = #{@comment_like.id}")
          .to be_nil
        
        expect(@adapter.run "SELECT id FROM likes_comments WHERE id = #{@comment_like.id}")
          .to be_nil
      end

      context "after removing paritions" do
        before do
          @adapter.remove_polymorphic_foreign_key(:likes, :comments, column: :likeable)
          @like = Like.create(likeable: comment)
        end

        it "works on a master table" do
          @like.destroy
          expect(@adapter.run "SELECT id FROM likes WHERE id = #{@comment_like.id}")
            .to be_nil
        end
      end
    end
  end

end
