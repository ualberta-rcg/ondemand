# frozen_string_literal: true

# OodAppLink is a representation of an HTML link to an OodApp.
class OodAppLink
  attr_reader :title, :description, :url, :icon_uri, :caption, :subtitle, :data, :tile

  def initialize(config = {})
    config = config.to_h.compact.symbolize_keys

    @title       = LocalizedValue.resolve(config.fetch(:title, ''))
    @subtitle    = LocalizedValue.resolve(config.fetch(:subtitle, ''))
    @description = LocalizedValue.resolve(config.fetch(:description, ''))
    @url         = LocalizedValue.resolve(config.fetch(:url, ''))
    @icon_uri    = URI(config.fetch(:icon_uri, 'fas://cog').to_s)
    @caption     = LocalizedValue.resolve_optional(config.fetch(:caption, nil))
    @new_tab     = config.fetch(:new_tab, true)
    @data        = config.fetch(:data, {}).to_h
    @tile        = LocalizedValue.resolve_tile_hash(config.fetch(:tile, {})).to_h.deep_symbolize_keys
  end

  def new_tab?
    @new_tab
  end

  def to_h
    instance_variables.each_with_object({}) do |var, hash|
      hash[var.to_s.gsub('@', '').to_sym] = instance_variable_get(var)
    end
  end

  def categorize(category: '', subcategory: '', show_in_menu: false)
    LinkCategorizer.new(self, category: category, subcategory: subcategory, show_in_menu: show_in_menu)
  end

  # Decorate an OodAppLink to look like an OodApp so it can be recategorized
  # in the menus.
  class LinkCategorizer < SimpleDelegator
    attr_reader :category, :subcategory

    def initialize(link, category: '', subcategory: '', show_in_menu: false)
      super(link)
      @category = LocalizedValue.resolve(category)
      @subcategory = LocalizedValue.resolve(subcategory)
      @show_in_menu = show_in_menu
    end

    def links
      [self]
    end

    def show_in_menu?
      @show_in_menu
    end
  end
end
