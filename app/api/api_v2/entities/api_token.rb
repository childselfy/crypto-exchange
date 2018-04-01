module APIv2
  module Entities
    class APIToken < Base
      expose :access_key
      expose :secret_key
    end
  end
end
