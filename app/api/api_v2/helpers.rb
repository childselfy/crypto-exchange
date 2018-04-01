module APIv2
  module Helpers

    def authenticate!
      current_user or raise AuthorizationError
    end

    def redis
      @r ||= KlineDB.redis
    end

    def current_user
      @current_user ||= current_token.try(:member)
    end

    def current_token
      @current_token ||= env['api_v2.token']
    end

    def current_market
      @current_market ||= Market.find params[:market]
    end

    def time_to
      params[:timestamp].present? ? Time.at(params[:timestamp]) : nil
    end

    def build_order(attrs)
      klass = attrs[:side] == 'sell' ? OrderAsk : OrderBid

      order = klass.new(
        source:        'APIv2',
        state:         ::Order::WAIT,
        member_id:     current_user.id,
        ask:           current_market.base_unit,
        bid:           current_market.quote_unit,
        currency:      current_market.id,
        ord_type:      attrs[:ord_type] || 'limit',
        price:         attrs[:price],
        volume:        attrs[:volume],
        origin_volume: attrs[:volume]
      )
    end

    def create_order(attrs)
      order = build_order attrs
      Ordering.new(order).submit
      order
    rescue
      Rails.logger.info "Failed to create order: #{$!}"
      Rails.logger.debug order.inspect
      Rails.logger.debug $!.backtrace.join("\n")
      raise CreateOrderError, $!
    end

    def create_orders(multi_attrs)
      orders = multi_attrs.map {|attrs| build_order attrs }
      Ordering.new(orders).submit
      orders
    rescue
      Rails.logger.info "Failed to create order: #{$!}"
      Rails.logger.debug $!.backtrace.join("\n")
      raise CreateOrderError, $!
    end

    def order_param
      params[:order_by].downcase == 'asc' ? 'id asc' : 'id desc'
    end

    def format_ticker(ticker)
      { at: ticker[:at],
        ticker: {
          buy: ticker[:buy],
          sell: ticker[:sell],
          low: ticker[:low],
          high: ticker[:high],
          last: ticker[:last],
          vol: ticker[:volume]
        }
      }
    end

    def get_k_json
      key = "peatio:#{params[:market]}:k:#{params[:period]}"

      if params[:timestamp]
        ts = JSON.parse(redis.lindex(key, 0)).first
        offset = (params[:timestamp] - ts) / 60 / params[:period]
        offset = 0 if offset < 0

        JSON.parse('[%s]' % redis.lrange(key, offset, offset + params[:limit] - 1).join(','))
      else
        length = redis.llen(key)
        offset = [length - params[:limit], 0].max
        JSON.parse('[%s]' % redis.lrange(key, offset, -1).join(','))
      end
    end

    def create_identity(params)
      @identity = Identity.new(email: params[:email], password: params[:password], password_confirmation: params[:confirm_password])
      if @identity.save
        make_auth_hash
        handle_member_object
      else
        raise RegistrationError, errors
      end
    end

    def make_auth_hash
      request.env["omniauth.auth"] = {
        "provider"=>"identity",
        "uid"=> @identity.id,
        "info"=> {"email"=> @identity.email },
        "credentials"=> {},
        "extra"=> {}
      }
    end

    def errors
      @identity.errors.full_messages.join(',')
    end

    def check_authentication
      raise LoginError unless identity
    end

    def identity
      @identity ||= Identity.authenticate(conditions, params[:password])
      make_auth_hash if @identity
    end

    def conditions
      {email: params[:email]}
    end

    def auth_hash
      @auth_hash ||= request.env["omniauth.auth"]
    end

    def handle_member_object
      @member = Member.from_auth(auth_hash)
      if @member
        if @member.disabled?
          raise RegistrationError, $! and return
        else
          #create_temporary_token # Will be used for KYC and Email Verification
          save_signup_history @member.id
          MemberMailer.notify_signin(@member.id).deliver if @member.activated?
        end
      else
        raise RegistrationError, $! and return
      end
      request.env["omniauth.auth"] = nil
      @member
    end

    def save_signup_history(member_id)
      SignupHistory.create(
        member_id: member_id,
        ip: request.ip,
        accept_language: request.headers["Accept-Language"],
        ua: request.headers["User-Agent"]
      )
    end
  end
end
