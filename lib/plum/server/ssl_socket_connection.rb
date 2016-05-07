# frozen-string-literal: true

module Plum
  class SSLSocketServerConnection < ServerConnection
    attr_reader :sock

    def initialize(sock, local_settings = {})
      @sock = sock
      super(@sock.method(:write), local_settings)

      if @sock.respond_to?(:cipher) # OpenSSL::SSL::SSLSocket-like
        if CIPHER_BLACKLIST.include?(@sock.cipher.first) # [cipher-suite, ssl-version, keylen, alglen]
          on(:negotiated) {
            raise RemoteConnectionError.new(:inadequate_security)
          }
        end
      end
    end

    # Closes the socket.
    def close
      super
      @sock.close
    end

    CIPHER_BLACKLIST = %w(
      NULL-MD5 NULL-SHA EXP-RC4-MD5 RC4-MD5 RC4-SHA EXP-RC2-CBC-MD5 IDEA-CBC-SHA EXP-DES-CBC-SHA DES-CBC-SHA DES-CBC3-SHA
      DH-DSS-DES-CBC-SHA DH-DSS-DES-CBC3-SHA DH-RSA-DES-CBC-SHA DH-RSA-DES-CBC3-SHA EXP-EDH-DSS-DES-CBC-SHA EDH-DSS-DES-CBC-SHA EDH-DSS-DES-CBC3-SHA EXP-EDH-RSA-DES-CBC-SHA EDH-RSA-DES-CBC-SHA EDH-RSA-DES-CBC3-SHA
      EXP-ADH-RC4-MD5 ADH-RC4-MD5 EXP-ADH-DES-CBC-SHA ADH-DES-CBC-SHA ADH-DES-CBC3-SHA AES128-SHA DH-DSS-AES128-SHA DH-RSA-AES128-SHA DHE-DSS-AES128-SHA DHE-RSA-AES128-SHA
      ADH-AES128-SHA AES256-SHA DH-DSS-AES256-SHA DH-RSA-AES256-SHA DHE-DSS-AES256-SHA DHE-RSA-AES256-SHA ADH-AES256-SHA NULL-SHA256 AES128-SHA256 AES256-SHA256
      DH-DSS-AES128-SHA256 DH-RSA-AES128-SHA256 DHE-DSS-AES128-SHA256 CAMELLIA128-SHA DH-DSS-CAMELLIA128-SHA DH-RSA-CAMELLIA128-SHA DHE-DSS-CAMELLIA128-SHA DHE-RSA-CAMELLIA128-SHA ADH-CAMELLIA128-SHA DHE-RSA-AES128-SHA256
      DH-DSS-AES256-SHA256 DH-RSA-AES256-SHA256 DHE-DSS-AES256-SHA256 DHE-RSA-AES256-SHA256 ADH-AES128-SHA256 ADH-AES256-SHA256 CAMELLIA256-SHA DH-DSS-CAMELLIA256-SHA DH-RSA-CAMELLIA256-SHA DHE-DSS-CAMELLIA256-SHA
      DHE-RSA-CAMELLIA256-SHA ADH-CAMELLIA256-SHA PSK-RC4-SHA PSK-3DES-EDE-CBC-SHA PSK-AES128-CBC-SHA PSK-AES256-CBC-SHA SEED-SHA DH-DSS-SEED-SHA DH-RSA-SEED-SHA DHE-DSS-SEED-SHA
      DHE-RSA-SEED-SHA ADH-SEED-SHA AES128-GCM-SHA256 AES256-GCM-SHA384 DH-RSA-AES128-GCM-SHA256 DH-RSA-AES256-GCM-SHA384 DH-DSS-AES128-GCM-SHA256 DH-DSS-AES256-GCM-SHA384 ADH-AES128-GCM-SHA256 ADH-AES256-GCM-SHA384
      ECDH-ECDSA-NULL-SHA ECDH-ECDSA-RC4-SHA ECDH-ECDSA-DES-CBC3-SHA ECDH-ECDSA-AES128-SHA ECDH-ECDSA-AES256-SHA ECDHE-ECDSA-NULL-SHA ECDHE-ECDSA-RC4-SHA ECDHE-ECDSA-DES-CBC3-SHA ECDHE-ECDSA-AES128-SHA ECDHE-ECDSA-AES256-SHA
      ECDH-RSA-NULL-SHA ECDH-RSA-RC4-SHA ECDH-RSA-DES-CBC3-SHA ECDH-RSA-AES128-SHA ECDH-RSA-AES256-SHA ECDHE-RSA-NULL-SHA ECDHE-RSA-RC4-SHA ECDHE-RSA-DES-CBC3-SHA ECDHE-RSA-AES128-SHA ECDHE-RSA-AES256-SHA
      AECDH-NULL-SHA AECDH-RC4-SHA AECDH-DES-CBC3-SHA AECDH-AES128-SHA AECDH-AES256-SHA SRP-3DES-EDE-CBC-SHA SRP-RSA-3DES-EDE-CBC-SHA SRP-DSS-3DES-EDE-CBC-SHA SRP-AES-128-CBC-SHA SRP-RSA-AES-128-CBC-SHA
      SRP-DSS-AES-128-CBC-SHA SRP-AES-256-CBC-SHA SRP-RSA-AES-256-CBC-SHA SRP-DSS-AES-256-CBC-SHA ECDHE-ECDSA-AES128-SHA256 ECDHE-ECDSA-AES256-SHA384 ECDH-ECDSA-AES128-SHA256 ECDH-ECDSA-AES256-SHA384 ECDHE-RSA-AES128-SHA256 ECDHE-RSA-AES256-SHA384
      ECDH-RSA-AES128-SHA256 ECDH-RSA-AES256-SHA384 ECDH-ECDSA-AES128-GCM-SHA256 ECDH-ECDSA-AES256-GCM-SHA384 ECDH-RSA-AES128-GCM-SHA256 ECDH-RSA-AES256-GCM-SHA384
    ).freeze
  end
end
