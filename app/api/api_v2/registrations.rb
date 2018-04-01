
module APIv2
  class Registrations < Grape::API

    helpers ::APIv2::NamedParams

    desc 'Sign up using Email and password and confirm password'
    params do
      use :registration
    end
    post "/signup" do
      member = create_identity params
      present member, with: APIv2::Entities::Member
    end

    desc 'Sign In using Email and Password'
    params do
      use :signin
    end
    post "/signin" do
      check_authentication
      member = handle_member_object
      raise ActivationError, 'Email Not Verified' unless member.activated?
    end
  end
end