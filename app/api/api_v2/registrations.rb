module APIv2
  class Registrations < Grape::API

    helpers ::APIv2::NamedParams

    desc 'Sign up using Email and password and confirm password'
    params do
      use :registration
    end
    post "/signup" do
      member = create_identity params
      member.generate_api_keys
      present member, with: APIv2::Entities::Member
    end

    desc 'Sign In using Email and Password'
    params do
      use :signin
    end
    post "/signin" do
      check_authentication
      member = handle_member_object
      api_tokens = member.api_tokens.last
      raise ActivationError, 'Email Not Verified' and return unless member.activated?
      present api_tokens, with: APIv2::Entities::APIToken
    end
  end
end