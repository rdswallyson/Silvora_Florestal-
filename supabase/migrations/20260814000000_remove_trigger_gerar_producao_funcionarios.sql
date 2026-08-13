-- Remove a trigger AFTER INSERT em producao porque o aplicativo Flutter
-- já insere os registros de producao_funcionarios manualmente via
-- ProducaoCalculoService.salvarProducao. Manter a trigger causava
-- duplicação dos registros para produções Individuais.

drop trigger if exists producao_gerar_funcionarios_trigger on public.producao;

-- Remove registros duplicados em producao_funcionarios, mantendo apenas
-- um registro por (producao_id, funcionario_id) quando houver duplicatas.
delete from public.producao_funcionarios
where id in (
  select id
  from (
    select
      id,
      row_number() over (
        partition by producao_id, funcionario_id
        order by created_at asc
      ) as rn
    from public.producao_funcionarios
  ) sub
  where rn > 1
);
