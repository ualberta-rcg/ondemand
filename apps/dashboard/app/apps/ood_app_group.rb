# OodAppGroup groups OodApps mostly through class methods. The object
# OodAppGroup is itself a group of OodApps.
class OodAppGroup
  attr_accessor :apps, :title, :canonical_title, :icon_uri, :sort

  def initialize(title: "", icon_uri: nil, apps: [], nav_limit: nil, sort: true, canonical_title: nil)
    @apps = apps
    @title = title
    @canonical_title = canonical_title.nil? ? title : canonical_title
    @icon_uri = URI(icon_uri.to_s) if icon_uri
    @nav_limit = nav_limit
    @sort = sort
  end

  def has_apps?
    apps.count > 0
  end

  def has_batch_connect_apps?
    return @has_batch_connect_apps unless @has_batch_connect_apps.nil?
    @has_batch_connect_apps = apps.any?(&:batch_connect_app?)
  end

  def nav_limit_caption
    if nav_limit < apps.size
      I18n.t('dashboard.nav_limit_caption', subset_count: nav_limit, total_count: apps.size)
    else
      ''
    end
  end

  def localized_title
    LocalizedValue.translate_category(title)
  end

  def title_with_nav_limit_caption
    if nav_limit_caption.present?
      "#{title} (#{nav_limit_caption})"
    else
      title
    end
  end

  def localized_title_with_nav_limit_caption
    base = localized_title
    if nav_limit_caption.present?
      "#{base} (#{nav_limit_caption})"
    else
      base
    end
  end

  def nav_limit
    @nav_limit || apps.size
  end

  def links
    apps.map(&:links).flatten
  end

  def to_h
    {
      :group => self,
      :apps => apps,
      :title => title,
      :icon_uri => icon_uri,
      :nav_limit => nav_limit,
      :sort => sort
    }
  end

  # Given an array of apps, group those apps by app category (or the attribute)
  # specified by 'group_by', potentially sorting both groups and apps arrays by title if sort is true.
  def self.groups_for(apps: [], group_by: :category, nav_limit: nil, sort: true)
    groups = apps.group_by { |app|
      app.respond_to?(group_by) ? app.send(group_by) : app.metadata[group_by]
    }.map { |k,v|
      canonical = if group_by == :category && v.first.respond_to?(:default_category)
                    v.first.default_category
                  elsif group_by == :subcategory && v.first.respond_to?(:default_subcategory)
                    v.first.default_subcategory
                  else
                    k
                  end
      OodAppGroup.new(title: k, canonical_title: canonical, apps: sort ? v.sort_by { |a| a.title } : v, nav_limit: nav_limit)
    }
    sort ? groups.sort_by { |g| [ g.title.to_s.empty? ? 1 : 0, g.title ] } : groups # make sure that the ungroupable app is always last
  end

  # Select a subset of groups by the specified array of titles
  # maintaining the order specified by the titles array.
  #
  # This way we can get a list of deployed sys apps, then group them by category
  # then select only the categories we want to display in the menu.
  def self.select(titles:[], groups:[])
    h = {}
    groups.each do |g|
      h[g.canonical_title] ||= g unless g.canonical_title.nil?
      h[g.title] = g
    end
    titles.map { |t| h.key?(t) ? h[t] : nil }.compact.uniq
  end
  
  # Append groups not in the specified array in alphabetical order at the end of
  # subset of groups in the titles array maintaining the order specified by the titles array.
  #
  # This way we can get a list of deployed sys apps, then group them by category,
  # then display categories in titles array in specific order,
  # then display other categories in alphabetical order
  def self.order(titles:[], groups:[])
    by_title = {}
    groups.each do |g|
      by_title[g.canonical_title] ||= g unless g.canonical_title.nil?
      by_title[g.title] = g
    end
    ordered = titles.map { |t| by_title[t] }.compact.uniq
    remaining = (groups - ordered).sort_by { |g| g.title.to_s }
    ordered + remaining
  end
end
