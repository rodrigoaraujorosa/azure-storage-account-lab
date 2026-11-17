# 🖱️ Publicação pelo Portal Azure

O mesmo ambiente dos scripts (`scripts/deploy.sh`), criado à mão no [Portal Azure](https://portal.azure.com). Siga na ordem: cada etapa usa algo da anterior.

Escolha um **sufixo** de 6 letras minúsculas e números (ex.: `k3x9pq`) e use o mesmo em todos os nomes. Em todos os recursos, na aba **Tags**, adicione `repo` = `azure-storage-account-lab`.

> Os nomes dos menus podem mudar um pouco com as atualizações do Portal. Se não achar um item, use a busca no topo da página do recurso.

## 1. Resource group

1. **Resource groups → + Create**.
2. **Resource group:** `rg-azure-storage-account-lab`; **Region:** `Brazil South`.
3. **Tags:** `repo` = `azure-storage-account-lab` → **Review + create → Create**.

## 2. Conta do frontend (static website)

1. **Storage accounts → + Create**.
2. **Basics:** resource group do lab, nome `stasalweb<sufixo>`, região `Brazil South`, **Performance** Standard, **Redundancy** LRS.
3. **Advanced:** desmarque *Allow enabling anonymous access on individual containers*; **Minimum TLS version** 1.2.
4. **Tags** → **Review + create → Create**.
5. Na conta criada: **Data management → Static website → Enabled**. **Index document name** e **Error document path**: `index.html` → **Save**.
6. Anote o **Primary endpoint** (ex.: `https://stasalweb<sufixo>.z15.web.core.windows.net/`). A **origem do frontend** é esse endereço sem a barra no fim. Ela é usada no CORS das etapas 3 e 5.

## 3. Conta de upload

1. **Storage accounts → + Create**: nome `stasalup<sufixo>`, mesma região, Standard, LRS.
2. **Advanced:**
   - desmarque *Allow enabling anonymous access on individual containers*;
   - desmarque **Enable storage account key access** (sem shared key: só Entra ID e user delegation SAS);
   - marque *Default to Microsoft Entra authorization in the Azure portal*;
   - **Minimum TLS version** 1.2; **Access tier** Hot.
3. **Data protection:** soft delete para blobs e para contêineres, **7 dias**.
4. **Tags** → **Review + create → Create**.
5. **Seu acesso aos dados:** sem shared key, o próprio Portal precisa de um papel de dados para mostrar o conteúdo. Na conta: **Access control (IAM) → + Add → Add role assignment → Storage Blob Data Contributor → Members: User, você → Review + assign**.
6. **Data storage → Containers → + Container:** nome `uploads`, **Anonymous access level** Private.
7. **Settings → Resource sharing (CORS) → aba Blob service**, uma linha:

   | Allowed origins | Allowed methods | Allowed headers | Exposed headers | Max age |
   | --- | --- | --- | --- | --- |
   | `<origem do frontend>,http://localhost:8080` | `PUT`, `OPTIONS` | `*` | `*` | `3600` |

   **Save**.

## 4. Function App (microserviço de SAS)

1. **Function App → + Create → Flex Consumption → Select**.
2. **Basics:** nome `func-azure-storage-account-lab-<sufixo>`, região (se `Brazil South` não aparecer, use a mais próxima disponível), **Runtime stack** Python, **Version** 3.12, **Instance size** 2048 MB.
3. **Storage:** crie ou escolha a conta `stasalfn<sufixo>` (storage interno da Function; não use a de upload).
4. **Monitoring:** Application Insights habilitado (útil para ver os logs).
5. **Tags** → **Review + create → Create**.
6. Na Function App: **Settings → Identity → System assigned → Status On → Save**.
7. **Papéis da identidade** (na conta de upload `stasalup<sufixo>`):
   - Na **conta**: **Access control (IAM) → Add role assignment → Storage Blob Delegator → Members: Managed identity → Function App → a do lab**.
   - No **contêiner** `uploads` (abra o contêiner): **Access Control (IAM) → Add role assignment → Storage Blob Data Contributor → mesma managed identity**.
8. **Settings → Environment variables → App settings**, adicione e clique em **Apply**:

   | Nome | Valor |
   | --- | --- |
   | `STORAGE_ACCOUNT_URL` | `https://stasalup<sufixo>.blob.core.windows.net` |
   | `UPLOAD_CONTAINER` | `uploads` |
   | `SAS_TTL_MINUTES` | `15` |
   | `MAX_UPLOAD_MB` | `400` |

9. **Código:** o plano Flex Consumption não permite editar nem enviar código pelo Portal. Use uma das opções:
   - **Cloud Shell** (ícone `>_` no topo do Portal, modo Bash):

     ```bash
     git clone https://github.com/rodrigoaraujorosa/azure-storage-account-lab.git
     cd azure-storage-account-lab/src/sas_service
     zip -qr ../../sas_service.zip . -x '__pycache__/*' 'local.settings*.json'
     cd ../..
     az functionapp deployment source config-zip -g rg-azure-storage-account-lab \
       -n func-azure-storage-account-lab-<sufixo> --src sas_service.zip --build-remote true
     ```

   - **VS Code** com a extensão *Azure Functions*: abra `src/sas_service`, clique com o botão direito na Function App e escolha **Deploy to Function App**.

10. Confira em **Overview → Functions** que aparece `create_upload_sas`.
11. **Functions → App keys → Host keys:** copie o valor da chave `default`. É a **function key** da etapa 5.

## 5. API Management

1. **API Management services → + Create**.
2. **Basics:** nome `apim-azure-storage-account-lab-<sufixo>`, região `Brazil South`, **Organization name** e **Administrator email** (os seus), **Pricing tier** Consumption.
3. **Tags** → **Review + create → Create**. Leva alguns minutos.
4. **APIs → Named values → + Add:**
   - **Name** e **Display name:** `sas-function-key`;
   - **Type:** Secret;
   - **Value:** a function key copiada na etapa 4.11 → **Save**.
5. **APIs → APIs → + Add API → HTTP (Manually define an HTTP API):**
   - **Display name:** `Upload SAS`; **Name:** `upload-sas`;
   - **Web service URL:** `https://<host da Function>/api`. O host está em **Function App → Overview → Default domain**;
   - **API URL suffix:** `uploads` → **Create**.
6. Na API, aba **Settings:** desmarque **Subscription required** → **Save**. Sem chave de assinatura, porque ela ficaria exposta no navegador.
7. Aba **Design → + Add operation**, duas vezes:

   | Display name | Método | URL |
   | --- | --- | --- |
   | `Gerar SAS de upload` | `POST` | `/sas` |
   | `Preflight CORS` | `OPTIONS` | `/sas` |

8. **Design → All operations → Inbound processing → `</>` (policy code editor)**. Cole o conteúdo de [`infra/apim/upload-sas-policy.xml`](../infra/apim/upload-sas-policy.xml), trocando:
   - `__WEB_ORIGIN__` pela origem do frontend (etapa 2.6);
   - `__LOCAL_ORIGIN__` por `http://localhost:8080`.

   **Save**.
9. Anote o **Gateway URL** em **Overview** (ex.: `https://apim-azure-storage-account-lab-<sufixo>.azure-api.net`).
10. **Teste rápido:** aba **Test → Gerar SAS de upload**, header `Content-Type: application/json`, corpo `{"fileName":"teste.bin","size":1048576}` → **Send**. Deve voltar `201` com `uploadUrl`.

## 6. Publicar o frontend

1. Copie `web/config.example.js` para `web/config.js` e troque `apiBaseUrl` por `<Gateway URL>/uploads`.
2. Na conta `stasalweb<sufixo>`: **Storage browser → Blob containers → `$web` → Upload**. Envie `index.html`, `app.js`, `styles.css` e `config.js`.
3. Abra a origem do frontend no navegador e envie um arquivo.

## 7. Limpeza

1. **Resource groups → `rg-azure-storage-account-lab` → Delete resource group**. Digite o nome para confirmar.
2. O APIM apagado fica em soft delete por 48 horas e segura o nome. Para liberar antes: **API Management services → Manage deleted APIMs** (no topo da lista) → selecione → **Purge**.
3. Registre no README, em "💸 Custos e limpeza", o custo e a data em que os recursos foram apagados.
