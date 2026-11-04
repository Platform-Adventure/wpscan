# frozen_string_literal: true

describe WPScan::Cache::Typhoeus do
  subject(:cache) { described_class.new(storage_path) }

  let(:storage_path) { Dir.mktmpdir }
  let(:request)      { Typhoeus::Request.new('http://example.com/', cache_ttl: 60) }
  let(:body)         { "\xFF\xD8binary".b }
  let(:response) do
    Typhoeus::Response.new(
      return_code: :ok,
      response_code: 200,
      response_headers: "HTTP/1.1 200 OK\r\nContent-Type: image/jpeg\r\nX-Test: \xE9\r\n\r\n".b,
      response_body: body,
      effective_url: 'http://example.com/',
      total_time: 0.5,
      debug_info: Ethon::Easy::DebugInfo.new
    )
  end

  after { FileUtils.rm_rf(storage_path) }

  describe '#set / #get' do
    it 'stores and returns the response' do
      cache.set(request, response)

      cached = cache.get(request)

      expect(cached).to be_a Typhoeus::Response
      expect(cached.return_code).to eql :ok
      expect(cached.code).to eql 200
      expect(cached.headers['Content-Type']).to eql 'image/jpeg'
      expect(cached.body).to eql body
      expect(cached.body.encoding).to eql body.encoding
      expect(cached.effective_url).to eql 'http://example.com/'
      expect(cached.total_time).to eql 0.5
      expect(cached.debug_info).to be_nil
    end

    context 'when the response is mocked' do
      let(:response) do
        Typhoeus::Response.new(code: 404, body: 'Not Found', headers: { 'X-Test' => 'a' }, return_code: :ok)
                          .tap { |res| res.mock = :webmock }
      end

      it 'stores and returns the response' do
        cache.set(request, response)

        cached = cache.get(request)

        expect(cached.code).to eql 404
        expect(cached.body).to eql 'Not Found'
        expect(cached.headers['X-Test']).to eql 'a'
      end
    end

    context 'when the response timed out' do
      let(:response) { Typhoeus::Response.new(return_code: :operation_timedout) }

      it 'does not store it' do
        cache.set(request, response)

        expect(cache.get(request)).to be_nil
      end
    end
  end
end
