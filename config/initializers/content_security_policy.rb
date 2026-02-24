# Be sure to restart your server when you modify this file.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.connect_src :self, "wss:", "ws:"
    policy.object_src  :none
    policy.base_uri    :self
  end

  # Automatically appends nonce-xxx to script-src for importmap and inline scripts.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
