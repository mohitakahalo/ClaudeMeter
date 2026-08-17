# Local code signing

`scripts/build-without-xcode.sh` signs the app with a certificate when one is
available, and falls back to an ad-hoc signature (`codesign --sign -`) when it
is not. The fallback works, so this whole document is optional.

## Creating the identity

No Apple Developer account is needed — a self-signed certificate is enough for a
locally built app.

```sh
cat > codesign.cnf <<'EOF'
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = v3_codesign

[ dn ]
CN = ClaudeMeter Local Signing

[ v3_codesign ]
basicConstraints     = critical,CA:FALSE
keyUsage             = critical,digitalSignature
extendedKeyUsage     = critical,codeSigning
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config codesign.cnf -keyout cmkey.pem -out cmcert.pem

# macOS cannot read PKCS#12 written with OpenSSL 3's modern defaults, so the
# older PBE algorithms have to be requested explicitly.
openssl pkcs12 -export -out cmid.p12 -inkey cmkey.pem -in cmcert.pem \
    -passout pass:cm -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

security import cmid.p12 -k ~/Library/Keychains/login.keychain-db \
    -P cm -T /usr/bin/codesign -A

# A self-signed certificate is not valid for signing until it is trusted for
# that purpose. Prompts for your password.
security add-trusted-cert -p codeSign \
    -k ~/Library/Keychains/login.keychain-db cmcert.pem
```

Verify, then delete `cmkey.pem` and `cmid.p12` — the private key lives in the
keychain from this point on:

```sh
security find-identity -v -p codesigning     # should list "ClaudeMeter Local Signing"
```

The build script picks the identity up by name. Override with
`SIGN_IDENTITY="Some Other Identity" ./scripts/build-without-xcode.sh`.

## What this does and does not fix

It gives the app a stable designated requirement:

```
identifier "com.eddmann.ClaudeMeter" and certificate leaf = H"<cert sha1>"
```

instead of one pinned to the binary's own hash. That is worth having if the app
is ever distributed, and it keeps the signature meaningful across rebuilds.

**It does not stop the keychain prompting again after a rebuild.** Reading
Claude Code's OAuth token means reading an item in the login keychain that
belongs to another application, and that item's ACL matches a trusted
application by its **code directory hash**, not by the designated requirement.
Measured on macOS 26:

| Action                                     | Prompt? |
| ------------------------------------------ | ------- |
| Relaunch the same binary                   | no      |
| Replace the bundle with identical bytes    | no      |
| Rebuild, same certificate, new binary      | **yes** |

So expect one "Always Allow" per rebuild. Answering it is enough until the next
build; day-to-day use never prompts.

Since the credential read runs off-actor with a bounded wait, an unanswered or
ignored prompt no longer freezes the app — it carries on without OAuth and picks
the credentials up on a later poll once the prompt is answered.
