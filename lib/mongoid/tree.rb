require 'active_support/concern'

module Mongoid
  ##
  # = Mongoid::Tree
  #
  # This module extends any Mongoid document with tree functionality.
  #
  # == Usage
  #
  # Simply include the module in any Mongoid document:
  #
  #   class Node
  #     include Mongoid::Document
  #     include Mongoid::Tree
  #   end
  #
  # === Using the tree structure
  #
  # Each document references many children. You can access them using the <tt>#children</tt> method.
  #
  #   node = Node.create
  #   node.children.create
  #   node.children.count # => 1
  #
  # Every document references one parent (unless it's a root document).
  #
  #   node = Node.create
  #   node.parent # => nil
  #   node.children.create
  #   node.children.first.parent # => node
  #
  # === Destroying
  #
  # Mongoid::Tree does not handle destroying of nodes by default. However it provides
  # several strategies that help you to deal with children of deleted documents. You can
  # simply add them as <tt>before_destroy</tt> callbacks.
  #
  # Available strategies are:
  #
  # * :nullify_children -- Sets the children's parent_id to null
  # * :move_children_to_parent -- Moves the children to the current document's parent
  # * :destroy_children -- Destroys all children by calling their #destroy method (invokes callbacks)
  # * :delete_descendants -- Deletes all descendants using a database query (doesn't invoke callbacks)
  #
  # Example:
  #
  #   class Node
  #     include Mongoid::Document
  #     include Mongoid::Tree
  #
  #     before_destroy :nullify_children
  #   end
  #
  # === Callbacks
  #
  # Mongoid::Tree offers callbacks for its rearranging process. This enables you to
  # rebuild certain fields when the document was moved in the tree. Rearranging happens
  # before the document is validated. This gives you a chance to validate your additional
  # changes done in your callbacks. See ActiveModel::Callbacks and ActiveSupport::Callbacks
  # for further details on callbacks.
  #
  # Example:
  #
  #   class Page
  #     include Mongoid::Document
  #     include Mongoid::Tree
  #
  #     after_rearrange :rebuild_path
  #
  #     field :slug
  #     field :path
  #
  #     private
  #
  #     def rebuild_path
  #       self.path = self.ancestors_and_self.collect(&:slug).join('/')
  #     end
  #   end
  #
  module Tree
    extend ActiveSupport::Concern

    autoload :Ordering, 'mongoid/tree/ordering'
    autoload :Traversal, 'mongoid/tree/traversal'

    included do
      has_many :children, :class_name => self.name, :foreign_key => :parent_id, :inverse_of => :parent, :validate => false

      belongs_to :parent, :class_name => self.name, :inverse_of => :children, :index => true, :validate => false

      field :parent_ids, :type => Array, :default => []
      index :parent_ids => 1

      field :depth, :type => Integer
      index :depth => 1

      set_callback :save, :after, :rearrange_children, :if => :rearrange_children?
      set_callback :validation, :before do
        run_callbacks(:rearrange) { rearrange }
      end

      validate :position_in_tree

      define_model_callbacks :rearrange, :only => [:before, :after]

      class_eval "def base_class; ::#{self.name}; end"
    end

    ##
    # This module implements class methods that will be available
    # on the document that includes Mongoid::Tree
    module ClassMethods

      ##
      # Returns the first root document
      #
      # @example
      #   Node.root
      #
      # @return [Mongoid::Document] The first root document
      def root
        roots.first
      end

      ##
      # Returns all root documents
      #
      # @example
      #   Node.roots
      #
      # @return [Mongoid::Criteria] Mongoid criteria to retrieve all root documents
      def roots
        where(:parent_id => nil)
      end

      ##
      # Returns all leaves (be careful, currently involves two queries)
      #
      # @example
      #   Node.leaves
      #
      # @return [Mongoid::Criteria] Mongoid criteria to retrieve all leave nodes
      def leaves
        where(:_id.nin => only(:parent_id).collect(&:parent_id))
      end

    end

    ##
    # @!method before_rearrange
    #   @!scope class
    #
    #   Sets a callback that is called before the document is rearranged
    #
    #   @example
    #     class Node
    #       include Mongoid::Document
    #       include Mongoid::Tree
    #
    #       before_rearrage :do_something
    #
    #     private
    #
    #       def do_something
    #         # ...
    #       end
    #     end
    #
    #   @note Generated by ActiveSupport
    #
    #   @return [undefined]

    ##
    # @!method after_rearrange
    #   @!scope class
    #
    #   Sets a callback that is called after the document is rearranged
    #
    #   @example
    #     class Node
    #       include Mongoid::Document
    #       include Mongoid::Tree
    #
    #       after_rearrange :do_something
    #
    #     private
    #
    #       def do_something
    #         # ...
    #       end
    #     end
    #
    #   @note Generated by ActiveSupport
    #
    #   @return [undefined]

    ##
    # @!method children
    #   Returns a list of the document's children. It's a <tt>references_many</tt> association.
    #
    #   @note Generated by Mongoid
    #
    #   @return [Mongoid::Criteria] Mongoid criteria to retrieve the document's children

    ##
    # @!method parent
    #   Returns the document's parent (unless it's a root document).  It's a <tt>referenced_in</tt> association.
    #
    #   @note Generated by Mongoid
    #
    #   @return [Mongoid::Document] The document's parent document

    ##
    # @!method parent=(document)
    #   Sets this documents parent document.
    #
    #   @note Generated by Mongoid
    #
    #   @param [Mongoid::Tree] document

    ##
    # @!method parent_ids
    #   Returns a list of the document's parent_ids, starting with the root node.
    #
    #   @note Generated by Mongoid
    #
    #   @return [Array<BSON::ObjectId>] The ids of the document's ancestors

    ##
    # Returns the depth of this document (number of ancestors)
    #
    # @example
    #   Node.root.depth # => 0
    #   Node.root.children.first.depth # => 1
    #
    # @return [Fixnum] Depth of this document
    def depth
      super || parent_ids.count
    end

    ##
    # Is this document a root node (has no parent)?
    #
    # @return [Boolean] Whether the document is a root node
    def root?
      parent_id.nil?
    end

    ##
    # Is this document a leaf node (has no children)?
    #
    # @return [Boolean] Whether the document is a leaf node
    def leaf?
      children.empty?
    end

    ##
    # Returns this document's root node. Returns `self` if the
    # current document is a root node
    #
    # @example
    #   node = Node.find(...)
    #   node.root
    #
    # @return [Mongoid::Document] The documents root node
    def root
      if parent_ids.present?
        base_class.find(parent_ids.first)
      else
        self.root? ? self : self.parent.root
      end
    end

    ##
    # Returns a chainable criteria for this document's ancestors
    #
    # @return [Mongoid::Criteria] Mongoid criteria to retrieve the documents ancestors
    def ancestors
      base_class.where(:_id.in => parent_ids).order(:depth => :asc)
    end

    ##
    # Returns an array of this document's ancestors and itself
    #
    # @return [Array<Mongoid::Document>] Array of the document's ancestors and itself
    def ancestors_and_self
      ancestors + [self]
    end

    ##
    # Is this document an ancestor of the other document?
    #
    # @param [Mongoid::Tree] other document to check against
    #
    # @return [Boolean] The document is an ancestor of the other document
    def ancestor_of?(other)
      other.parent_ids.include?(self.id)
    end

    ##
    # Returns a chainable criteria for this document's descendants
    #
    # @return [Mongoid::Criteria] Mongoid criteria to retrieve the document's descendants
    def descendants
      base_class.where(:parent_ids => self.id)
    end

    ##
    # Returns and array of this document and it's descendants
    #
    # @return [Array<Mongoid::Document>] Array of the document itself and it's descendants
    def descendants_and_self
      [self] + descendants
    end

    ##
    # Is this document a descendant of the other document?
    #
    # @param [Mongoid::Tree] other document to check against
    #
    # @return [Boolean] The document is a descendant of the other document
    def descendant_of?(other)
      self.parent_ids.include?(other.id)
    end

    ##
    # Returns this document's siblings
    #
    # @return [Mongoid::Criteria] Mongoid criteria to retrieve the document's siblings
    def siblings
      siblings_and_self.excludes(:id => self.id)
    end

    ##
    # Returns this document's siblings and itself
    #
    # @return [Mongoid::Criteria] Mongoid criteria to retrieve the document's siblings and itself
    def siblings_and_self
      base_class.where(:parent_id => self.parent_id)
    end

    ##
    # Is this document a sibling of the other document?
    #
    # @param [Mongoid::Tree] other document to check against
    #
    # @return [Boolean] The document is a sibling of the other document
    def sibling_of?(other)
      self.parent_id == other.parent_id
    end

    ##
    # Returns all leaves of this document (be careful, currently involves two queries)
    #
    # @return [Mongoid::Criteria] Mongoid criteria to retrieve the document's leaves
    def leaves
      base_class.where(:_id.nin => base_class.only(:parent_id).collect(&:parent_id)).and(:parent_ids => self.id)
    end

    ##
    # Forces rearranging of all children after next save
    #
    # @return [undefined]
    def rearrange_children!
      @rearrange_children = true
    end

    ##
    # Will the children be rearranged after next save?
    #
    # @return [Boolean] Whether the children will be rearranged
    def rearrange_children?
      !!@rearrange_children
    end

    ##
    # Nullifies all children's parent_id
    #
    # @return [undefined]
    def nullify_children
      children.each do |c|
        c.parent = c.parent_id = nil
        c.save
      end
    end

    ##
    # Moves all children to this document's parent
    #
    # @return [undefined]
    def move_children_to_parent
      children.each do |c|
        c.parent = self.parent
        c.save
      end
    end

    ##
    # Deletes all descendants using the database (doesn't invoke callbacks)
    #
    # @return [undefined]
    def delete_descendants
      base_class.delete_all(:conditions => { :parent_ids => self.id })
    end

    ##
    # Destroys all children by calling their #destroy method (does invoke callbacks)
    #
    # @return [undefined]
    def destroy_children
      children.destroy_all
    end

  private

    ##
    # Updates the parent_ids and marks the children for
    # rearrangement when the parent_ids changed
    #
    # @private
    # @return [undefined]
    def rearrange
      if self.parent_id
        self.parent_ids = parent ? parent.parent_ids + [self.parent_id] : [self.parent_id]
      else
        self.parent_ids = []
      end

      self.depth = parent_ids.size

      rearrange_children! if self.parent_ids_changed?
    end

    def rearrange_children
      @rearrange_children = false
      self.children.each { |c| c.save }
    end

    def position_in_tree
      errors.add(:parent_id, :invalid) if self.parent_ids.include?(self.id)
    end
  end
end
