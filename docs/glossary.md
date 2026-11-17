# 📖 Glossário

Termos, siglas e jargão usados no README e na documentação deste lab.

| Termo | O que é |
| --- | --- |
| AKS | Azure Kubernetes Service: Kubernetes gerenciado do Azure; no cenário real, roda o microserviço Node.js que emite a SAS |
| APIM | Azure API Management: gateway que publica APIs e aplica policies (CORS, autenticação, limites) antes do backend |
| Blob | Arquivo guardado no Azure Blob Storage, dentro de um contêiner |
| Bloco (*block*) | Pedaço de um blob enviado com Put Block; o Put Block List junta os blocos, na ordem, no blob final |
| CORS | Cross-Origin Resource Sharing: regras que dizem de quais sites o navegador pode chamar um serviço |
| Entra ID | Microsoft Entra ID, o serviço de identidade da Microsoft (antigo Azure Active Directory) |
| Flex Consumption | Plano do Azure Functions cobrado por uso, que escala até zero |
| Function key | Chave exigida para chamar uma Function com nível de autorização `function`; aqui só o APIM a conhece |
| Identidade gerenciada (*managed identity*) | Identidade do Entra ID criada para um recurso do Azure, sem senha nem chave para guardar |
| Ingress | Ponto de entrada HTTP de um cluster Kubernetes, que encaminha as requisições para os serviços |
| mTLS | Mutual TLS: TLS em que cliente e servidor apresentam certificado, e cada lado confirma a identidade do outro |
| Named value | Variável do APIM usada nas policies; pode ser secreta, como a function key |
| Partida a frio (*cold start*) | Atraso da primeira chamada depois que o serviço escalou até zero e precisa subir uma instância |
| Preflight | Requisição `OPTIONS` que o navegador faz antes da chamada real para conferir o CORS |
| Resource group | Grupo de recursos do Azure; apagar o grupo apaga tudo dentro dele |
| SAS | Shared Access Signature: URL assinada que dá acesso temporário e limitado a um recurso do Storage |
| Shared key | Chave de acesso da conta de armazenamento, que dá acesso total; neste lab fica desabilitada |
| Static website | Recurso do Storage que serve arquivos do contêiner `$web` como site estático |
| User delegation SAS | SAS assinada com uma chave obtida via Entra ID (*user delegation key*), em vez da shared key |
| VNet | Virtual Network: rede privada no Azure, onde recursos se comunicam sem passar pela internet |
| Workload Identity | Recurso do AKS que associa a service account de um pod a uma identidade do Entra ID, sem segredo no cluster |
