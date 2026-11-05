# frozen_string_literal: true

module WPScan
  module Model
    class WpItem
      # Fetches and exposes the public wordpress.org info API response for a
      # plugin or theme. The HTTP call is performed at most once per item.
      module WordpressOrgData
        # Timeout (in seconds) for the wordpress.org API lookup. Kept low so a
        # slow or unreachable wordpress.org does not noticeably stall the scan.
        WORDPRESS_ORG_API_TIMEOUT = 5

        # @return [ String, nil ] The wordpress.org API URL returning info for
        #   this item. Subclasses override this; nil disables the lookup.
        def wordpress_org_api_url
          nil
        end

        # @return [ Hash ] Empty hash if the item is not on wordpress.org or the
        #   lookup fails.
        def wordpress_org_data
          return @wordpress_org_data if defined?(@wordpress_org_data)

          @wordpress_org_data = fetch_wordpress_org_data
        end

        # Number of active installs as reported by the wordpress.org API.
        # See https://codex.wordpress.org/WordPress.org_API
        #
        # @return [ Integer, nil ]
        def active_installs
          wordpress_org_data['active_installs']
        end

        private

        # @return [ Hash ]
        def fetch_wordpress_org_data
          url = wordpress_org_api_url
          return {} unless url

          # Typhoeus.get is used rather than Browser.get so that target-only options
          # (http auth, cookies, custom headers, vhost, Referer) are not sent to wordpress.org
          res = Typhoeus.get(url, wordpress_org_request_params)
          return {} unless res.code == 200

          data = JSON.parse(res.body)
          data.is_a?(Hash) ? data : {}
        rescue StandardError
          {}
        end

        # @return [ Hash ] Connection-only params (timeouts, proxy, TLS) for the wordpress.org API
        def wordpress_org_request_params
          browser = Browser.instance
          params  = browser.default_connect_request_params.merge(
            connecttimeout: WORDPRESS_ORG_API_TIMEOUT,
            timeout: WORDPRESS_ORG_API_TIMEOUT,
            accept_encoding: 'gzip, deflate',
            headers: { 'User-Agent' => browser.default_user_agent }
          )

          if browser.proxy_auth
            params[:proxyuserpwd] = "#{browser.proxy_auth[:username]}:#{browser.proxy_auth[:password]}"
          end

          if ParsedCli.proxy_target_only
            params.delete(:proxy)
            params.delete(:proxyuserpwd)
          end

          params
        end
      end

      include WordpressOrgData
    end
  end
end
