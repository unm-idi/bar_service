require "bar_service/version"
require 'bar_service/role_cache'
require 'httparty'
require 'redis'

module BarService
  extend self

  class Configuration
    attr_reader :roles, :whitelist
    attr_accessor :api_endpoint, :user_name, :user_password, :redis_url

    def initialize
      @whitelist = {}
      @roles = {}
    end

    def roles=(role_hsh)
      if roles_valid?(role_hsh)
        @roles = role_hsh.to_a.map{|k,v| [k.to_s, v.to_s]}.to_h
        @whitelist = @roles.values.map{|v| [v, nil] }.to_h
      else
        raise "Bar role hash incorrectly formatted"
      end
    end

    def method_missing(m, *args, &block)
      if valid_whitelist_assignment?(m.to_s, args.first)
        return @whitelist[m.to_s.chomp('_whitelist=')] = args.first.map(&:to_s)
      elsif valid_whitelist_get?(m.to_s)
        return @whitelist[m.to_s.chomp('_whitelist')]
      end

      super
    end

    def available_whitelists
      @whitelist.map{ |k,v| k if v }.compact
    end


    private

    def role_structure_valid?(role_hsh)
      !(role_hsh.is_a?(Hash) && role_hsh.map do |role|
        valid_array_elements?(role) && role.size == 2
      end.include?(false))
    end

    def roles_valid?(role_hsh)
      !!(if role_structure_valid?(role_hsh)
        values = role_hsh.to_a.transpose.second
        values == values.uniq
      end)
    end

    def valid_whitelist_key?(method)
      @whitelist.keys.include? method.chomp('=').chomp('_whitelist')
    end

    def valid_whitelist_assignment?(method, args)
      method.index('_whitelist=') && valid_whitelist_key?(method) &&
      valid_whitelist_array?(args)
    end

    def valid_whitelist_array?(arry)
      arry.is_a?(Array) && valid_array_elements?(arry)
    end

    def valid_whitelist_get?(method)
      method.index(/_whitelist$/) &&
      valid_whitelist_key?(method.to_s)
    end

    def valid_array_elements?(arry)
      !arry.map{|r| r.is_a?(String) || r.is_a?(Symbol)}.include?(false)
    end
  end


  def configuration
    @@configuration ||= Configuration.new
  end

  def configure
    yield(configuration) if block_given?
    configuration
  end

  def bar_roles(user)
    whitelist_roles = configuration.available_whitelists.map do |role|
      role if configuration.whitelist[role].include?(user)
    end.compact

    api_roles = if configuration.api_endpoint.present?
      bar_role_auth(user, whitelist_roles)
    end

    (whitelist_roles + (api_roles ||= [])).sort
  end

  private

  def bar_role_auth(user, current_roles)
    if configuration.redis_url.present? && RoleCache.has_key?(user)
      RoleCache.bar_roles user
    elsif configuration.redis_url.present?
      RoleCache.set_roles user, bar_authorize(user, current_roles)
    else
      bar_authorize(user, current_roles)
    end
  end

  def bar_authorize(user, current_roles)
    configuration.roles.map do |bar, role|
      role if !current_roles.include?(role) && bar_api_check?(user, bar)
    end.compact
  end

  def bar_api_check?(netid, bar_route)
    HTTParty.get(bar_uri(netid, bar_route), basic_auth: auth_hsh).body == 'Y'
  end

  def auth_hsh
    {username: configuration.user_name, password: configuration.user_password}
  end

  def bar_uri(netid, bar_route)
    URI.parse(configuration.api_endpoint.gsub(':net_id', netid).gsub(':bar_role', bar_route))
  end

end
