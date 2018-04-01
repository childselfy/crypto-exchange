module APIv2
  module RegistrationHelpers

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
          raise ActivationError, 'Account Disabled.'
        else
          save_signup_history @member.id
          MemberMailer.notify_signin(@member.id).deliver if @member.activated?
        end
      else
        raise RegistrationError, $! and return
      end
      request.env["omniauth.auth"] = nil
      @member
    end

    def generate_api_keys(member)
      member.api_tokens.create(scopes: 'all')
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