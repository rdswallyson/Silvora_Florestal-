-- SILVORA — Tabela de historico de precos por cliente
-- Data: 2026-08-06
-- Projeto: Silvora Florestal (jkwnynwxxfesaagifkhq)

CREATE TABLE IF NOT EXISTS public.cliente_precos (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  owner_id uuid NOT NULL DEFAULT auth.uid(),
  cliente_id uuid NOT NULL REFERENCES public.clientes(id) ON DELETE CASCADE,
  valor_m3 numeric NOT NULL,
  vigente_desde date NOT NULL DEFAULT current_date,
  vigente_ate date,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.cliente_precos ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'cliente_precos'
      AND policyname = 'cliente_precos_own'
  ) THEN
    CREATE POLICY cliente_precos_own ON public.cliente_precos
      FOR ALL
      USING (owner_id = auth.uid())
      WITH CHECK (owner_id = auth.uid());
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_cliente_precos_cliente_vigencia
  ON public.cliente_precos(cliente_id, vigente_desde DESC);

-- Funcao auxiliar para fechar vigencia anterior ao inserir novo preco
CREATE OR REPLACE FUNCTION public.fechar_vigencia_anterior_cliente_preco()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  UPDATE public.cliente_precos
  SET vigente_ate = NEW.vigente_desde
  WHERE cliente_id = NEW.cliente_id
    AND id != NEW.id
    AND owner_id = NEW.owner_id
    AND vigente_ate IS NULL;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_fechar_vigencia_cliente_preco ON public.cliente_precos;
CREATE TRIGGER trg_fechar_vigencia_cliente_preco
  AFTER INSERT ON public.cliente_precos
  FOR EACH ROW
  EXECUTE FUNCTION public.fechar_vigencia_anterior_cliente_preco();

GRANT ALL ON public.cliente_precos TO authenticated;
GRANT ALL ON public.cliente_precos TO anon;
GRANT ALL ON public.cliente_precos TO service_role;
