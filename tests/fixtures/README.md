# Dados sintéticos de teste

loopback-test-cert.pem e loopback-test-key.pem formam um certificado autoassinado e uma chave de teste publicamente distribuídos. São usados somente pelo teste de HTTPS em 127.0.0.1. Não são credenciais da OpenAI e não são carregados pelo gateway em produção.

O teste demonstra recusa do certificado sem confiança e aceitação somente quando a CA de teste é passada explicitamente ao cliente de teste. O adaptador de produção usa validação TLS padrão e endpoint fixo api.openai.com.
