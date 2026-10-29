-- =====================================================================
-- OVINOCAPRINOCULTURA DE CORTE
-- RODAR NO BANCO LOCAL  api_sisateg   (F5 uma vez; leva alguns minutos)
-- Cria TRÊS tabelas (nomes próprios, para não misturar com a bovinocultura no servidor):
--   public.resumo_ovino_propriedades        -> 1 linha por propriedade (ativas e inativas com lançamento): produtor, técnico,
--                                              supervisor (SisATeG), município, áreas, projeto e datas do vínculo.
--   public.resumo_ovino_mensal              -> 1 linha por propriedade e mês: animais vendidos, receita bruta e despesa direta.
--   public.resumo_ovino_despesa_subgrupo    -> despesa direta por subgrupo e mês (a soma dos subgrupos = despesa direta).
-- Regras do corte (mesmo raciocínio da bovinocultura; CONFERIR com o relatório do SisATeG de um técnico):
--   valor do lançamento = QUANTIDADE x VALOR_UNITARIO (mesma visita e mesmo item)
--   venda_animais_rs  = receita do subgrupo "Venda de Animal Vivo" (abate fica fora, como na planilha)
--   animais_vendidos  = quantidade (cabeças) desses mesmos subgrupos
--   (venda de animal para abate fica FORA da receita bruta, como na planilha do SisATeG; guardada em venda_abate_rs)
--   receita_bruta     = venda de animais, esterco, volumoso excedente, pele, lã e outras receitas;
--                       NÃO conta empréstimo (recebimento) nem investimento (venda de bem)
--   despesa_direta    = despesas menos empréstimo, investimento (aquisição de bem), "Aleitamento artificial",
--                       "Despesas com Formação de Forrageiras perene", "Mão de obra familiar" e a compra de animais
--                       lançada como investimento / animal de serviço. A compra de animais para recria/terminação (subgrupo "Aquisição de Animais") NÃO conta: a planilha do SisATeG não a soma no Total Despesas.
-- =====================================================================

DROP TABLE IF EXISTS public.resumo_ovino_propriedades;
CREATE TABLE public.resumo_ovino_propriedades AS
WITH ativas AS (  -- propriedades ATIVAS que têm vínculo ATIVO de OVINOCAPRINOCULTURA DE CORTE
  SELECT id_propriedade, MAX(produtor) AS produtor, MAX(NULLIF(tecnico_atual,'')) AS tecnico_a,
         MAX(NULLIF(supervisor_atual,'')) AS supervisor_a
  FROM public.propriedades_ativas_na_ateg
  WHERE id_propriedade::text IN (
        SELECT id_propriedade::text FROM public.sisateg_vinculo_propriedade
        WHERE atividade ILIKE '%OVINOCAPRINOCULTURA%CORTE%' AND UPPER(status_vinculo) = 'ATIVO')
  GROUP BY 1
),
lanc_ids AS (  -- toda propriedade que já teve lançamento do corte (ativa ou não) desde o início da base
  SELECT DISTINCT id_propriedade FROM public.sisateg_receita_despesa
  WHERE atividade = 'OVINOCAPRINOCULTURA DE CORTE' AND status_item = 'ATIVO' AND tipo_registro = 'PRINCIPAL'
    AND dt_referencia >= DATE '2024-06-01'
),
todas AS (  -- ativas + inativas que têm lançamento (ativa = TRUE/FALSE)
  SELECT id_propriedade, produtor, tecnico_a, supervisor_a, TRUE AS ativa FROM ativas
  UNION ALL
  SELECT l.id_propriedade, NULL, NULL, NULL, FALSE FROM lanc_ids l
  WHERE l.id_propriedade NOT IN (SELECT id_propriedade FROM ativas)
),
acomp AS (
  SELECT id_propriedade, MAX(tecnico_atual) AS tecnico_m, MAX(tecnico_responsavel) AS tecnico_r,
         MAX(supervisor_atual) AS supervisor_m, MAX(produtor) AS produtor_m, MAX(imovel) AS imovel_m
  FROM public.acompanhamento_mensal_visitas
  WHERE id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
nome AS (
  SELECT id_propriedade, MAX(propriedade) AS propriedade
  FROM public.sisateg_rel_indicador_padrao_mensal
  WHERE propriedade IS NOT NULL AND id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
area AS (  -- área produtiva: usa a do cadastro; se for 0/vazia, usa a do relatório de indicadores do SisATeG (a mesma da planilha oficial)
  SELECT d.id_propriedade, MAX(d.area_total) AS area_total,
         COALESCE(NULLIF(MAX(d.area_atividades_produtivas), 0), MAX(i.area_prod)) AS area_produtiva,
         MAX(d.municipio) AS municipio, MAX(d.uf) AS uf
  FROM public.dim_propriedade d
  LEFT JOIN (SELECT id_propriedade::text AS idp, MAX(NULLIF(area_produtiva::text, '')::numeric) AS area_prod
             FROM public.sisateg_rel_indicador_padrao_mensal GROUP BY 1) i ON i.idp = d.id_propriedade::text
  WHERE d.id_propriedade IN (SELECT id_propriedade FROM todas) GROUP BY 1
),
vinc AS (
  SELECT id_propriedade::text AS idp, id_projeto, projeto, status_vinculo, motivo_desativacao,
         dt_inicio::date AS ini, dt_fim::date AS fim
  FROM public.sisateg_vinculo_propriedade
  WHERE atividade ILIKE '%OVINOCAPRINOCULTURA%CORTE%' AND id_propriedade::text IN (SELECT id_propriedade::text FROM todas)
),
vu AS (  -- um vínculo por propriedade: o ATIVO (se houver) de início mais recente
  SELECT DISTINCT ON (idp) idp, id_projeto, projeto, ini, fim, status_vinculo, motivo_desativacao
  FROM vinc
  ORDER BY idp, (UPPER(status_vinculo) = 'ATIVO') DESC, ini DESC, fim DESC NULLS FIRST
),
nproj AS (SELECT idp, COUNT(DISTINCT id_projeto) AS qtd_projetos FROM vinc GROUP BY 1)
SELECT a.id_propriedade,
       COALESCE(n.propriedade, ac.imovel_m) AS propriedade,
       COALESCE(a.produtor, ac.produtor_m) AS produtor,
       btrim(COALESCE(a.tecnico_a, ac.tecnico_m, ac.tecnico_r), E' \t\r\n') AS tecnico,
       COALESCE(a.supervisor_a, ac.supervisor_m)         AS supervisor_sisateg,
       ar.municipio, ar.uf,
       ROUND(ar.area_total::numeric, 2)    AS area_total,
       ROUND(ar.area_produtiva::numeric, 2) AS area_produtiva,
       vu.projeto, np.qtd_projetos,
       vu.ini AS inicio_projeto, vu.fim AS fim_projeto,
       vu.status_vinculo, vu.motivo_desativacao, a.ativa
FROM todas a
LEFT JOIN acomp ac ON ac.id_propriedade = a.id_propriedade
LEFT JOIN nome n   ON n.id_propriedade  = a.id_propriedade
LEFT JOIN area ar  ON ar.id_propriedade = a.id_propriedade
LEFT JOIN vu       ON vu.idp = a.id_propriedade::text
LEFT JOIN nproj np ON np.idp = a.id_propriedade::text;

CREATE INDEX ON public.resumo_ovino_propriedades (id_propriedade);
CREATE INDEX ON public.resumo_ovino_propriedades (tecnico);

-- ---------------------------------------------------------------------
-- ---------------------------------------------------------------------
-- Visitas excluídas no SisATeG (dt_exclusao_visita preenchida) ficam de fora
DROP TABLE IF EXISTS tmp_visitas_invalidas;
CREATE TEMP TABLE tmp_visitas_invalidas AS
  SELECT DISTINCT id_visita::text AS id FROM public.sisateg_rel_listar_visita
  WHERE dt_exclusao_visita IS NOT NULL;
CREATE INDEX ON tmp_visitas_invalidas (id);
ANALYZE tmp_visitas_invalidas;

-- Filtra a tabela grande UMA vez só; os resumos abaixo usam esta cópia menor (bem mais rápido)
DROP TABLE IF EXISTS tmp_base;
CREATE TEMP TABLE tmp_base AS
SELECT r.* FROM public.sisateg_receita_despesa r
WHERE r.atividade = 'OVINOCAPRINOCULTURA DE CORTE' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'PRINCIPAL'
  AND r.dt_referencia >= DATE '2024-06-01' AND r.dt_referencia < CURRENT_DATE + 1
  AND NOT EXISTS (SELECT 1 FROM tmp_visitas_invalidas iv WHERE iv.id = r.id_visita::text)
  AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_ovino_propriedades);
CREATE INDEX ON tmp_base (id_visita, id_item);
ANALYZE tmp_base;
-- Preço ATIVO que só existe como DETALHADO (o SisATeG usa): entra quando o item tem quantidade ativa e NENHUM preço ativo principal
INSERT INTO tmp_base
SELECT r.* FROM public.sisateg_receita_despesa r
WHERE r.atividade = 'OVINOCAPRINOCULTURA DE CORTE' AND r.status_item = 'ATIVO' AND r.tipo_registro = 'DETALHADO'
  AND r.tipo_valor = 'VALOR_UNITARIO' AND r.valor IS NOT NULL
  AND r.dt_referencia >= DATE '2024-06-01' AND r.dt_referencia < CURRENT_DATE + 1
  AND NOT EXISTS (SELECT 1 FROM tmp_visitas_invalidas iv WHERE iv.id = r.id_visita::text)
  AND r.id_propriedade IN (SELECT id_propriedade FROM public.resumo_ovino_propriedades)
  AND EXISTS (SELECT 1 FROM tmp_base q WHERE q.id_visita = r.id_visita AND q.id_item = r.id_item AND q.dt_referencia = r.dt_referencia AND q.tipo_valor = 'QUANTIDADE')
  AND NOT EXISTS (SELECT 1 FROM tmp_base p WHERE p.id_visita = r.id_visita AND p.id_item = r.id_item AND p.dt_referencia = r.dt_referencia AND p.tipo_valor = 'VALOR_UNITARIO');
UPDATE tmp_base SET tipo_registro = 'PRINCIPAL' WHERE tipo_registro = 'DETALHADO';   -- (só as linhas de preço acrescentadas acima eram detalhadas)
-- O mês de cada visita é o da REFERÊNCIA DA VISITA (é assim que a planilha do SisATeG conta); a data do item só vale se a visita não tiver referência
UPDATE tmp_base b SET dt_referencia = to_date(lv.referencia_visita || '-01', 'YYYY-MM-DD')
FROM public.sisateg_rel_listar_visita lv
WHERE lv.id_visita::text = b.id_visita::text AND lv.referencia_visita ~ '^[0-9]{4}-[0-9]{2}$'
  AND ABS(to_date(lv.referencia_visita || '-01', 'YYYY-MM-DD') - b.dt_referencia::date) <= 366;   -- referência muito distante da data do item (ex.: visita antiga editada depois) é ignorada
-- Visita SEM referência válida: o mês dela passa a ser o mais recente entre os itens dela
UPDATE tmp_base b SET dt_referencia = m.mx
FROM (SELECT b2.id_visita, MAX(b2.dt_referencia) AS mx
      FROM tmp_base b2
      WHERE NOT EXISTS (SELECT 1 FROM public.sisateg_rel_listar_visita lv
                        WHERE lv.id_visita::text = b2.id_visita::text AND lv.referencia_visita ~ '^[0-9]{4}-[0-9]{2}$')
      GROUP BY 1) m
WHERE m.id_visita = b.id_visita AND b.dt_referencia < m.mx;
CREATE INDEX ON tmp_base (id_propriedade, id_visita);
ANALYZE tmp_base;

-- técnico de cada visita (só das visitas que interessam), com índice
DROP TABLE IF EXISTS tmp_av;
CREATE TEMP TABLE tmp_av AS
  SELECT av.id_visita::text AS id, MAX(btrim(av.tecnico_responsavel, E' \t\r\n')) AS tecnico
  FROM public.acompanhamento_mensal_visitas av
  WHERE av.id_visita::text IN (SELECT DISTINCT id_visita::text FROM tmp_base)
  GROUP BY 1;
CREATE INDEX ON tmp_av (id);
ANALYZE tmp_av;

DROP TABLE IF EXISTS public.resumo_ovino_mensal;
-- Etapas (cada uma vira tabela temporária; o tempo de cada uma aparece na tela)
DROP TABLE IF EXISTS tmp_q;
CREATE TEMP TABLE tmp_q AS
  SELECT id_propriedade, grupo, id_visita, id_item, dt_referencia, subgrupo, item, SUM(valor) AS qtd
  FROM tmp_base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7;
DROP TABLE IF EXISTS tmp_pr;
CREATE TEMP TABLE tmp_pr AS
  SELECT id_propriedade, grupo, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM tmp_base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4,5;
CREATE INDEX ON tmp_q (id_propriedade, id_visita, id_item);
CREATE INDEX ON tmp_pr (id_propriedade, id_visita, id_item);
ANALYZE tmp_q;
ANALYZE tmp_pr;
DROP TABLE IF EXISTS tmp_v;
CREATE TEMP TABLE tmp_v AS
  SELECT q.id_propriedade, date_trunc('month', q.dt_referencia)::date AS mes,
         q.grupo, q.subgrupo, q.item, q.qtd, q.qtd * pr.preco AS valor
  FROM tmp_q q JOIN tmp_pr pr USING (id_propriedade, grupo, id_visita, id_item, dt_referencia);
ANALYZE tmp_v;
DROP TABLE IF EXISTS tmp_fin;
CREATE TEMP TABLE tmp_fin AS
  SELECT id_propriedade, mes,
    SUM(qtd) FILTER (WHERE grupo = 'Receita' AND subgrupo ILIKE 'Venda de Animal Vivo%') AS animais_vendidos,
    SUM(valor) FILTER (WHERE grupo = 'Receita' AND subgrupo ILIKE 'Venda de Animal Vivo%') AS venda_animais_rs,
    SUM(valor) FILTER (WHERE grupo = 'Receita'
         AND subgrupo NOT ILIKE 'Empr%' AND subgrupo NOT ILIKE 'Investimento%'
         AND subgrupo NOT ILIKE 'Venda de Animal Abate%') AS receita_bruta,
    SUM(valor) FILTER (WHERE grupo = 'Receita' AND subgrupo ILIKE 'Venda de Animal Abate%') AS venda_abate_rs,
    SUM(valor) FILTER (WHERE grupo = 'Despesa'
         AND subgrupo NOT ILIKE 'Empr%' AND subgrupo NOT ILIKE 'Investimento%') AS despesa_total,
    SUM(valor) FILTER (WHERE grupo = 'Despesa'
         AND subgrupo NOT ILIKE 'Empr%' AND subgrupo NOT ILIKE 'Investimento%'
         AND subgrupo NOT ILIKE 'Aleitamento%' AND subgrupo NOT ILIKE 'Despesas com Forma%' AND subgrupo NOT ILIKE 'Aquisi%de Animais'
         AND item NOT ILIKE 'M_o de obra familiar'
         AND item NOT ILIKE 'Aquisi%de animais (investimento)%' AND item NOT ILIKE 'Aquisi%de animais de servi%') AS despesa_direta,
    SUM(valor) FILTER (WHERE grupo = 'Despesa' AND item ILIKE 'M_o de obra familiar') AS mao_obra_familiar,
    SUM(valor) FILTER (WHERE grupo = 'Despesa' AND subgrupo ILIKE 'Aleitamento%') AS despesa_aleitamento
  FROM tmp_v GROUP BY 1,2;
DROP TABLE IF EXISTS tmp_tec;
CREATE TEMP TABLE tmp_tec AS
  -- técnico responsável pela visita daquele mês (técnico da época)
  SELECT b.id_propriedade, date_trunc('month', b.dt_referencia)::date AS mes, MAX(av.tecnico) AS tecnico
  FROM tmp_base b JOIN tmp_av av ON av.id = b.id_visita::text
  GROUP BY 1, 2;
DROP TABLE IF EXISTS tmp_vis;
CREATE TEMP TABLE tmp_vis AS
  -- visita(s) do mês (normalmente uma); serve para conferir com a planilha do SisATeG
  SELECT id_propriedade, date_trunc('month', dt_referencia)::date AS mes, string_agg(DISTINCT id_visita::text, ',' ORDER BY id_visita::text) AS id_visita
  FROM tmp_base GROUP BY 1, 2;
ANALYZE tmp_fin;
ANALYZE tmp_tec;
ANALYZE tmp_vis;

CREATE TABLE public.resumo_ovino_mensal AS
SELECT f.id_propriedade,
       to_char(f.mes, 'YYYY-MM') AS mes,
       t.tecnico,
       vm.id_visita,
       ROUND(f.animais_vendidos::numeric, 1)     AS animais_vendidos,
       ROUND(f.venda_animais_rs::numeric, 2)     AS venda_animais_rs,
       ROUND(f.receita_bruta::numeric, 2)        AS receita_bruta,
       ROUND(f.venda_abate_rs::numeric, 2)       AS venda_abate_rs,
       ROUND(f.despesa_direta::numeric, 2)       AS despesa_direta,
       ROUND(f.mao_obra_familiar::numeric, 2)    AS mao_obra_familiar,
       ROUND(f.despesa_aleitamento::numeric, 2)  AS despesa_aleitamento,
       ROUND(f.despesa_total::numeric, 2)        AS despesa_total
FROM tmp_fin f
LEFT JOIN tmp_tec t ON t.id_propriedade = f.id_propriedade AND t.mes = f.mes
LEFT JOIN tmp_vis vm ON vm.id_propriedade = f.id_propriedade AND vm.mes = f.mes;

CREATE INDEX ON public.resumo_ovino_mensal (id_propriedade);
CREATE INDEX ON public.resumo_ovino_mensal (tecnico);
CREATE INDEX ON public.resumo_ovino_mensal (mes);
-- ---------------------------------------------------------------------
-- Despesa direta por SUBGRUPO e mês (mesma regra da despesa_direta acima; a soma dos subgrupos = despesa_direta)
DROP TABLE IF EXISTS public.resumo_ovino_despesa_subgrupo;
CREATE TABLE public.resumo_ovino_despesa_subgrupo AS
WITH base AS (
  SELECT r.* FROM tmp_base r
  WHERE r.grupo = 'Despesa'
),
q AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, subgrupo, item, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6
),
pr AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4
)
SELECT q.id_propriedade, to_char(date_trunc('month', q.dt_referencia), 'YYYY-MM') AS mes, q.subgrupo,
       ROUND(SUM(q.qtd * pr.preco)::numeric, 2) AS valor
FROM q JOIN pr USING (id_propriedade, id_visita, id_item, dt_referencia)
WHERE q.subgrupo NOT ILIKE 'Empr%' AND q.subgrupo NOT ILIKE 'Investimento%'
  AND q.subgrupo NOT ILIKE 'Aleitamento%' AND q.subgrupo NOT ILIKE 'Despesas com Forma%' AND q.subgrupo NOT ILIKE 'Aquisi%de Animais'
  AND q.item NOT ILIKE 'M_o de obra familiar'
  AND q.item NOT ILIKE 'Aquisi%de animais (investimento)%' AND q.item NOT ILIKE 'Aquisi%de animais de servi%'
GROUP BY 1,2,3;
CREATE INDEX ON public.resumo_ovino_despesa_subgrupo (id_propriedade, mes);

-- Receitas e despesas por TIPO (subgrupo) e classe: alimenta a aba "Receitas e despesas".
--   classe: Receita bruta | Fora da receita bruta (abate, empréstimo, investimento)
--           Despesa direta | Outras despesas (formação, mão de obra familiar, compra de animal como investimento)
--           | Aleitamento (fora do total) | Fora das despesas (empréstimo/investimento)
DROP TABLE IF EXISTS public.resumo_ovino_tipo;
CREATE TABLE public.resumo_ovino_tipo AS
WITH base AS (
  SELECT r.* FROM tmp_base r
  WHERE r.grupo IN ('Receita','Despesa')
),
q AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, grupo, subgrupo, item, SUM(valor) AS qtd
  FROM base WHERE tipo_valor = 'QUANTIDADE' GROUP BY 1,2,3,4,5,6,7
),
pr AS (
  SELECT id_propriedade, id_visita, id_item, dt_referencia, AVG(valor) AS preco
  FROM base WHERE tipo_valor = 'VALOR_UNITARIO' GROUP BY 1,2,3,4
),
v AS (
  SELECT q.id_propriedade, to_char(date_trunc('month', q.dt_referencia), 'YYYY-MM') AS mes, q.grupo, q.subgrupo,
         CASE WHEN q.grupo = 'Receita' AND q.subgrupo ILIKE 'Venda de Animal Abate%' THEN 'Fora da receita bruta'
              WHEN q.subgrupo ILIKE 'Empr%' OR q.subgrupo ILIKE 'Investimento%' THEN
                CASE WHEN q.grupo = 'Receita' THEN 'Fora da receita bruta' ELSE 'Fora das despesas' END
              WHEN q.grupo = 'Receita' THEN 'Receita bruta'
              WHEN q.grupo = 'Despesa' AND (q.subgrupo ILIKE 'Aleitamento%' OR q.subgrupo ILIKE 'Aquisi%de Animais') THEN 'Aleitamento (fora do total)'   -- aleitamento e compra de animais p/ recria-terminação: a planilha do SisATeG não soma no Total Despesas
              WHEN q.subgrupo ILIKE 'Despesas com Forma%'
                   OR q.item ILIKE 'M_o de obra familiar'
                   OR q.item ILIKE 'Aquisi%de animais (investimento)%' OR q.item ILIKE 'Aquisi%de animais de servi%' THEN 'Outras despesas'
              ELSE 'Despesa direta' END AS classe,
         q.qtd * pr.preco AS valor
  FROM q JOIN pr USING (id_propriedade, id_visita, id_item, dt_referencia)
)
SELECT id_propriedade, mes, grupo, classe, subgrupo, ROUND(SUM(valor)::numeric, 2) AS valor
FROM v GROUP BY 1,2,3,4,5;
CREATE INDEX ON public.resumo_ovino_tipo (id_propriedade, mes);

ANALYZE public.resumo_ovino_propriedades;
ANALYZE public.resumo_ovino_mensal;

-- Conferência: propriedades e quantas têm lançamento de corte
SELECT (SELECT COUNT(*) FROM public.resumo_ovino_propriedades) AS propriedades,
       (SELECT COUNT(DISTINCT id_propriedade) FROM public.resumo_ovino_mensal) AS com_lancamento,
       (SELECT COUNT(*) FROM public.resumo_ovino_mensal) AS linhas_mensais,
       (SELECT MAX(mes) FROM public.resumo_ovino_mensal) AS ultimo_mes;
