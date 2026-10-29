# Painel de acompanhamento mensal: Ovinocaprinocultura de corte

Mesmo painel da bovinocultura (FastAPI + Chart.js na Vercel), adaptado ao corte.
Lê as views `vw_ovino_mensal`, `vw_ovino_propriedades` e `vw_ovino_despesa_subgrupo` do banco `painel_ateg`.
Não mexe nas views da bovinocultura (nomes próprios).

## O que o painel mostra
Receita bruta, despesa direta, venda de animais, preço médio por animal, animais vendidos (cabeças),
margem bruta da atividade, margem da venda de animais e animais vendidos por produtor.
Abas: Visão macro, Gráficos, Destaques do mês, Causas, Receitas e despesas, Tabela mensal (+ Excel) e Conferência com a planilha do SisATeG. Filtro de Região, e o projeto TREINAMENTO SP nunca aparece.

## Regras do corte (conferir com o SisATeG de um técnico)
- Valor do lançamento = QUANTIDADE x VALOR_UNITARIO. Atividade OVINOCAPRINOCULTURA DE CORTE, status ATIVO, tipo PRINCIPAL.
- Venda de animais = subgrupos "Venda de Animal Vivo" + "Venda de Animal Abate". Animais vendidos = quantidade desses subgrupos.
- Receita bruta = tudo da receita menos empréstimo e investimento (venda de bem).
- Despesa direta = despesas menos empréstimo, investimento, aleitamento artificial, formação de forrageiras perene,
  mão de obra familiar e compra de animais lançada como investimento / animal de serviço.
  A compra de animais para recria/terminação (COE) CONTA como despesa direta. (hipótese a validar)
- Entradas/saídas de propriedades: pelo primeiro/último mês com lançamento (a venda de corte é irregular, não dá para usar só a venda).
- O painel começa em jun/2024 (`MES_INICIO` no SQL e no app; o corte tem dados desde 2020).

## Rotina
Veja `PASSO_A_PASSO_ATUALIZACAO.md`. Resumo: todo dia `python scripts/atualizar_tudo.py --rapido` (ou `atualizar_ovino.bat`); o painel lê o banco do servidor, então só precisa de `git push` quando o código mudar.

## Primeira publicação (uma vez)
- Copiar o `.env` da bovinocultura para esta pasta (sem TABLE_NAME; veja .env.example).
- Rodar `sql/usuario_leitura.sql` só se o usuário `painel_leitura` ainda não existir (ele já existe). O script de cópia já reaplica o GRANT.
- Criar o repositório novo no GitHub e o projeto novo na Vercel apontando para esta pasta.
