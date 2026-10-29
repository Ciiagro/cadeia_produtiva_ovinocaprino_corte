# Atualização do painel da Ovinocaprinocultura de corte (passo a passo)

Pasta do projeto: `C:\CIIAGRO2\painel_cadeias\Ovinocaprinocultura`
Use o **Git Bash**: `cd /c/CIIAGRO2/painel_cadeias/Ovinocaprinocultura`
(No Git Bash, rode os comandos `python scripts/...`. No Explorer, os `.bat` funcionam com dois cliques.)

O corte usa a MESMA tabela de carga da bovinocultura e da apicultura (`sisateg_receita_despesa`).
Por isso, se você acabou de atualizar a bovinocultura (ou a apicultura), **não precisa baixar de novo**: use `--so-resumo`.

## Qual comando usar

| Quando | Comando | .bat | Tempo |
|---|---|---|---|
| Bovinocultura ou Apicultura acabou de atualizar (o mais comum) | `python scripts/atualizar_tudo.py --so-resumo` | `atualizar_so_resumo.bat` | curto |
| Atualizar sozinho (baixa do SisATeG) | `python scripts/atualizar_tudo.py --rapido` | `atualizar_ovino.bat` | poucos minutos |
| Toda semana (olha 120 dias) | `python scripts/atualizar_tudo.py` | `atualizar_ovino_completo.bat` | mais demorado |
| **1ª vez com o SQL novo, ou mudou o SQL** | `python scripts/atualizar_tudo.py --so-resumo --completo` | `atualizar_so_resumo_completo.bat` | só refaz o resumo |
| Recarregar a história | `python scripts/atualizar_tudo.py --desde 2024-06-01` | `atualizar_historia_completa.bat` | 15 a 20 min |

## Primeira vez com esta versão
1. `python scripts/atualizar_tudo.py --so-resumo --completo`
2. Espere aparecer **"Pronto"**.
3. Ctrl+F5 no painel.
4. Aba **Conferência**: suba a planilha do SisATeG do ovino de corte (um mês) e veja se bate.

## Rotina diária (todo dia)
1. Abra o Git Bash e entre na pasta: `cd /c/CIIAGRO2/painel_cadeias/Ovinocaprinocultura`
2. Rode: `python scripts/atualizar_tudo.py --rapido` (ou dois cliques em `atualizar_ovino.bat`). Recarrega só os últimos 45 dias.
3. Espere aparecer **"Pronto"** e aperte Ctrl+F5 no painel.
- Os dados vão direto para o banco do servidor: **não precisa de `git push`** nem de nova publicação na Vercel.
- Se a Bovinocultura acabou de ser atualizada, aqui basta `python scripts/atualizar_tudo.py --so-resumo` (mais rápido).
- Visitas: se precisar, rode antes `C:\CIIAGRO2\integracao_ateg_painel_servidor\atualizar_visitas.bat`.
- Se der erro, nada é trocado no servidor (transação única). Rode de novo.

## Rotina semanal
`python scripts/atualizar_tudo.py` (completo, olha 120 dias), ou quando algum mês antigo parecer errado.

## Quando precisa de `git push`
Só quando o **código** mudar (app, SQL, scripts). Atualizar dados não exige. Se mudar o SQL, rode antes `python scripts/atualizar_tudo.py --so-resumo --completo` e depois faça o commit e o push. Se o Git reclamar de `.lock`: `rm -f .git/refs/heads/main.lock .git/index.lock`.

## Regras (iguais às da bovinocultura)
- O mês da visita é a `referencia_visita` da tabela de visitas (se válida e a até 366 dias da data do item). Sem referência, vale a data mais recente dos itens.
- Visitas excluídas no SisATeG (`dt_exclusao_visita`) ficam de fora.
- Se o item tem quantidade ativa e não tem preço principal ativo, usa o preço detalhado ativo.
- O projeto **TREINAMENTO SP** nunca aparece (filtros, gráficos, tabelas, Excel e Conferência).
- Supervisor = o do `ranking_tecnicos` (uma linha por técnico, a com mais visitas); se o técnico não estiver no ranking, o do SisATeG.
- Valor do lançamento = QUANTIDADE x VALOR_UNITARIO. Atividade OVINOCAPRINOCULTURA DE CORTE, status ATIVO, tipo PRINCIPAL.
- Venda de animais = subgrupo "Venda de Animal Vivo". Animais vendidos = cabeças desse subgrupo. A venda para abate fica FORA da receita bruta (como na planilha do SisATeG), mas entra na conferência em "Receitas".
- Receita bruta = receita menos empréstimo, investimento (venda de bem) e venda para abate.
- Despesa direta = despesa menos empréstimo, investimento, aleitamento artificial, formação de forrageiras perene, mão de obra familiar e compra de animais lançada como investimento / animal de serviço. A compra de animais para recria/terminação (subgrupo "Aquisição de Animais") NÃO conta, porque a planilha do SisATeG não a soma no Total Despesas; ela aparece na aba Receitas e despesas como "fora do total".

## Conferência com a planilha
- Se a planilha não tiver ID da Visita: casa pelo **ID da Propriedade** (se tiver ID da Visita, casa por ele). Compara Receitas (receita bruta + venda para abate, venda de bem e empréstimo), Despesas Diretas e, se a planilha tiver, os animais vendidos.
- Esperado: 0 diferenças. Visitas "sem lançamento de corte" são normais.
- Para ver o que o SisATeG tem numa visita: `python scripts/consultar_visita.py <id_visita>`.

## Se der erro
- `Unsupported content type` no ODBC: rode de novo (a carga tenta 3 vezes por mês).
- pgAdmin travado: veja `pg_stat_activity` e use `pg_terminate_backend(pid)`. Nunca `DROP ... CASCADE`.
- Rode SQL do banco local só em `api_sisateg`. O servidor é `painel_ateg`.
