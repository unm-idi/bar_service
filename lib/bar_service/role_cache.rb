module RoleCache
  extend self

  def redis_endpoint
    @@redis_endpoint ||= Redis.new(url: BarService.configuration.redis_url)
  end

  def bar_roles(user)
    redis_endpoint.hkeys(user).reject{ |role| role == 'no_bar_roles' }
  end

  def remove_roles(user)
    redis_endpoint.del user
  end

  def set_roles(user, roles=[])
    remove_roles user
    roles.each { |role| redis_endpoint.hset(user, role, true) }
    redis_endpoint.hset(user, 'no_bar_roles', true) if roles.empty?
    redis_endpoint.expire user, expiration
    bar_roles user
  end

  def has_key?(user)
    redis_endpoint.exists user
  end

  private

  def expiration
    (expiration_date - Time.now).to_i
  end

  def expiration_date
    tt = Time.now.utc + 86400
    Time.new(tt.year, tt.month, tt.day).utc + 10800
  end

end
