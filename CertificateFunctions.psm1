function New-CertificateRequest {
    [CmdletBinding()]
    param (
            [int]
            [ValidateSet(2048, 4096, 8192, 16384)]
            # The length of the key.  The default is 2048.
            $KeyLength=2048,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            # The "CN=" value of the certificates' Subject field.
            $CommonName,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            # The "OU=" value of the certificates' Subject field.
            $OrganizationalUnit,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            # The "O=" value of the certificate's Subject field.
            $Organization,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            # The "L=" value of the certificate's Subject field.
            $Locality,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            # The "S=" value of the certificate's Subject field.
            $State,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]
            # The "C=" value of the certificate's Subject field.
            $Country,

            [Parameter(Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string[]]
            # An array of alternative names that should be bound to the
            # certificate's public key.
            $SubjectAlternateNames,

            [Parameter(Mandatory=$false)]
            [string]
            # An optional friendly name for the certificate.
            $FriendlyName,

            [Parameter(Mandatory=$false)]
            [string]
            # An option description of the certificate.
            $Description
          )

    BEGIN {
        # The "magic numbers" section.
        # There is no really good reason for this to be in the BEGIN block,
        # except that it sets these contant-value-type things apart from
        # the actual code.

        # The name of the cryptographic provider.  Specifying this also sets the
        # key's ProviderType.  In this case, the ProviderType is
        # XCN_PROV_RSA_SCHANNEL.
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa379427.aspx
        $ProviderName = "Microsoft RSA SChannel Cryptographic Provider"

        # This is an SDDL string specifying that the
        # NT AUTHORITY\SYSTEM and the BUILTIN\Administrators group have
        # basically all rights to the certificate request, and that
        # NT AUTHORITY\NETWORK SERVICE has Read, List, and Create Child rights.
        # See the big scariness here:
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa772285.aspx
        $SecurityDescriptor = "D:PAI(A;;0xd01f01ff;;;SY)(A;;0xd01f01ff;;;BA)(A;;0x80120089;;;NS)"

        # This is a X509KeySpec enum value that states that the key can be
        # used for signing.
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa379409.aspx
        $X509KeySpecKeyExchange = 1

        # The X509CertificateEnrollmentContext enum specifies that
        # "ContextMachine" is 0x2, which means store the certificate in the
        # Machine store.
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa379399.aspx
        $X509CertEnrollmentContextMachine = 2

        # Requested Extensions:
        #   X509v3 Key Usage: critical
        #       Digital Signature, Non Repudiation, Key Encipherment, Data Encipherment
        #
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa379410.aspx
        # X509KeyUsageFlags:
        #   XCN_CERT_DIGITAL_SIGNATURE_KEY_USAGE   = 0x80
        #   XCN_CERT_NON_REPUDIATION_KEY_USAGE     = 0x40
        #   XCN_CERT_KEY_ENCIPHERMENT_KEY_USAGE    = 0x20
        #   XCN_CERT_DATA_ENCIPHERMENT_KEY_USAGE   = 0x10
        #   == 0xF0 (240) when OR'ed together.
        $RequestedExtensions = 0xF0

        #   X509v3 Extended Key Usage:
        #       TLS Web Server Authentication
        #
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa378132.aspx
        #   XCN_OID_PKIX_KP_SERVER_AUTH = 1.3.6.1.5.5.7.3.1
        #       "The certificate can be used for OCSP authentication."
        #
        $RequestedEnhancedExtensions = "1.3.6.1.5.5.7.3.1"

        # The AlternativeNameType enum value specifying that an item in the
        # SubjectAlternativeNames list is a DNS name.
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa374830.aspx
        $XCNCertAltNameDnsName = 3

        # The EncodingType enum value specifying that the encoding should
        # be represented as a Certificate Request.  It puts the
        # -----BEGIN NEW CERTIFICATE REQUEST-----
        # -----END NEW CERTIFICATE REQUEST-----
        # text before and after the CSR.
        #
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa374936.aspx
        $XCNCryptStringBase64RequestHeader = 0x3
    }

    PROCESS {
        # Create the private key.
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa378921.aspx
        $key = New-Object -ComObject "X509Enrollment.CX509PrivateKey.1"
        $key.ProviderName = $ProviderName
        $key.KeySpec = $X509KeySpecKeyExchange
        $key.Length = $KeyLength
        $key.SecurityDescriptor = $SecurityDescriptor
        $key.MachineContext = $true

        $key.Create()
        if (!$key.Opened) {
            Write-Error "Could not create and open a private key."
            return
        }
        Write-Verbose "Created private key."

        # Initialize the Certificate Request.
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa377505.aspx
        $certreq = New-Object -ComObject "X509Enrollment.CX509CertificateRequestPkcs10.1"
        $certreq.InitializeFromPrivateKey($X509CertEnrollmentContextMachine, $key, $null)

        # Set the Subject.
        $subject = "CN={0},OU={1},O={2},L={3},S={4},C={5}" -f
                    $CommonName,
                    $OrganizationalUnit,
                    $Organization,
                    $Locality,
                    $State,
                    $Country
        Write-Verbose "Subject: $Subject"
        $distinguishedName = New-Object -ComObject "X509Enrollment.CX500DistinguishedName.1"
        $distinguishedName.Encode($subject)
        $certreq.Subject = $distinguishedName
        # IIS sets this for some reason, so we will, too.
        $certreq.SMimeCapabilities = $true

        $ExtensionKeyUsage = New-Object -ComObject "X509Enrollment.CX509ExtensionKeyUsage.1"
        $ExtensionKeyUsage.InitializeEncode($RequestedExtensions)
        $ExtensionKeyUsage.Critical = $true
        # Add the requested extensions to the certificate request.
        $certreq.X509Extensions.Add($ExtensionKeyUsage)

        $EnhancedKeyUsageOid = New-Object -ComObject "X509Enrollment.CObjectId.1"
        $EnhancedKeyUsageOid.InitializeFromValue($RequestedEnhancedExtensions)
        $EnhancedKeyUsageOids = New-Object -ComObject "X509Enrollment.CObjectIds.1"
        $EnhancedKeyUsageOids.Add($EnhancedKeyUsageOid)
        $EnhancedKeyUsage = New-Object -ComObject "X509Enrollment.CX509ExtensionEnhancedKeyUsage.1"
        $EnhancedKeyUsage.InitializeEncode($EnhancedKeyUsageOids)
        # Add the requested enhanced usage extensions to the certificate request.
        $certreq.X509Extensions.Add($EnhancedKeyUsage)

        # If the user specified that the certificate should include
        # alternative names, add them to the CSR.
        $alternativeNames = $null
        if ($SubjectAlternateNames.Count -gt 0) {
            for ($i = 0; $i -lt $SubjectAlternateNames.Count; $i++) {
                $name = $SubjectAlternateNames[$i]
                if ([String]::IsNullOrEmpty($name)) {
                    Write-Warning "Requested SAN entry with index of $i was null"
                    continue
                }
                $altName = New-Object -ComObject "X509Enrollment.CAlternativeName.1"
                $altName.InitializeFromString($XCNCertAltNameDnsName, $name)
                if ($alternativeNames -eq $null) {
                    $alternativeNames = New-Object -ComObject "X509Enrollment.CAlternativeNames.1"
                }
                $alternativeNames.Add($altName)
                Write-Verbose "SubjectAlternativeName: DNS:$($name)"
            }
            if ($alternativeNames.Count -gt 0) {
                $ExtensionAlternativeNames = New-Object -ComObject "X509Enrollment.CX509ExtensionAlternativeNames.1"
                $ExtensionAlternativeNames.InitializeEncode($alternativeNames)
                # Add the requested Subject Alternative Names to the certificate request.
                $certreq.X509Extensions.Add($ExtensionAlternativeNames)
            }
        }

        # The CX509Enrollment object is what actually puts the CSR into the
        # certificate store and prints out the CSR for submission to a CA.
        # http://msdn.microsoft.com/en-us/library/windows/desktop/aa377809.aspx
        $enrollment = New-Object -ComObject "X509Enrollment.CX509Enrollment.1"
        $enrollment.InitializeFromRequest($certreq)

        if ([String]::IsNullOrEmpty($Description) -eq $false) {
            $enrollment.CertificateDescription = $Description
        }

        if ([String]::IsNullOrEmpty($FriendlyName) -eq $false) {
            $enrollment.CertificateFriendlyName = $FriendlyName
        }

        Write-Verbose "Creating Certificate Request"
        $csr = $enrollment.CreateRequest($XCNCryptStringBase64RequestHeader)
        Write-Verbose "Certificate Request created."

        if ($key.Opened) {
            Write-Verbose "Closing private key"
            $key.Close()
        }

        return $csr
    }
}