import 'dart:async';
import 'package:flutter/material.dart';
import '../services/db_service.dart';
import '../theme/app_theme.dart';

class _Msg {
  final String text;
  final bool fromUser;
  _Msg(this.text, this.fromUser);
}

class IaScreen extends StatefulWidget {
  const IaScreen({super.key});
  @override
  State<IaScreen> createState() => _IaScreenState();
}

class _IaScreenState extends State<IaScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [
    _Msg('Olá! Sou a SILVORA IA 🌲 Posso gerar relatórios, calcular '
        'produtividade, custo por m³, consumo de combustível e muito mais. '
        'Como posso ajudar?', false),
  ];

  bool _thinking = false;

  final _sugestoes = const [
    'Qual a produção de hoje?',
    'Custo por m³ da equipe Bravo',
    'Quais manutenções estão previstas?',
    'Lucro por viagem de ontem',
  ];

  void _send(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add(_Msg(text, true));
      _thinking = true;
    });
    _controller.clear();
    _scrollToBottom();
    final resposta = await _responder(text);
    if (mounted) {
      setState(() {
        _messages.add(_Msg(resposta, false));
        _thinking = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  Future<String> _responder(String q) async {
    final l = q.toLowerCase();
    try {
      if (l.contains('produç') || l.contains('hoje') || l.contains('m³')) {
        final hoje = DateTime.now().toIso8601String().split('T').first;
        final producoes = await Db.list('producao', select: '*');
        final hojeList = producoes.where((m) => '${m['data']}'.startsWith(hoje));
        final volume = hojeList.fold<double>(
            0, (s, m) => s + (double.tryParse('${m['volume_m3']}') ?? 0));
        final arvores = hojeList.fold<int>(
            0, (s, m) => s + (int.tryParse('${m['arvores']}') ?? 0));
        if (producoes.isEmpty) return 'Ainda não há registros de produção.';
        return 'Hoje foram produzidos ${volume.toStringAsFixed(1)} m³ e ${arvores.toStringAsFixed(0)} árvores em ${hojeList.length} registros.';
      }
      if (l.contains('custo') || l.contains('metro')) {
        final producoes = await Db.list('producao', select: '*');
        if (producoes.isEmpty) return 'Não há produção registrada para calcular o custo.';
        final map = <String, List<Map<String, dynamic>>>{};
        for (final p in producoes) {
          final e = '${p['equipe_id']}';
          map.putIfAbsent(e, () => []).add(p);
        }
        String? maiorId;
        double maiorCusto = 0;
        for (final e in map.entries) {
          if (e.key.isEmpty || e.key == 'null') continue;
          final volume = e.value.fold<double>(0,
              (s, m) => s + (double.tryParse('${m['volume_m3']}') ?? 0));
          final despesas = e.value.fold<double>(0, (s, m) {
            final tipo = '${m['tipo_pagamento']}';
            final unit = double.tryParse('${m['valor_unitario']}') ?? 0;
            final v = double.tryParse('${m['volume_m3']}') ?? 0;
            final a = int.tryParse('${m['arvores']}') ?? 0;
            if (tipo == 'Diária' || tipo == 'Tarefa') return s + unit;
            if (tipo == 'Árvore') return s + a * unit;
            return s + v * unit;
          });
          final custo = volume > 0 ? despesas / volume : 0;
          if (custo > maiorCusto) {
            maiorCusto = custo;
            maiorId = e.key;
          }
        }
        if (maiorId == null) return 'Dados insuficientes para calcular custo por m³.';
        final equipe = await Db.list('equipes', select: '*')
            .then((l) => l.firstWhere((m) => '${m['id']}' == maiorId,
                orElse: () => <String, dynamic>{}));
        return 'O custo por m³ da equipe ${equipe['nome'] ?? maiorId} está em R\$ ${maiorCusto.toStringAsFixed(2)}. Recomendo revisar o consumo de combustível e produtividade.';
      }
      if (l.contains('manuten')) {
        final equipamentos = await Db.list('equipamentos', select: '*');
        final pendentes = equipamentos
            .where((m) => '${m['situacao']}' == 'Manutenção')
            .toList();
        if (pendentes.isEmpty) return 'Não há manutenções pendentes no momento.';
        return '${pendentes.length} equipamento(s) em manutenção: ${pendentes.map((m) => m['nome']).join(', ')}.';
      }
      if (l.contains('lucro') || l.contains('viagem')) {
        final transporte = await Db.list('transporte', select: '*');
        if (transporte.isEmpty) return 'Não há viagens registradas ainda.';
        final total = transporte.fold<double>(
            0, (s, m) => s + (double.tryParse('${m['frete']}') ?? 0));
        return 'O faturamento total com fretes é de R\$ ${total.toStringAsFixed(2)} em ${transporte.length} viagens.';
      }
      if (l.contains('estoque') || l.contains('produto')) {
        final estoque = await Db.list('estoque', select: '*');
        final baixo = estoque.where((m) {
          final q = int.tryParse('${m['quantidade']}') ?? 0;
          final min = int.tryParse('${m['minimo']}') ?? 0;
          return q <= min && min > 0;
        }).toList();
        if (baixo.isEmpty) return 'Estoque sob controle. Nenhum item abaixo do mínimo.';
        return '${baixo.length} item(ns) com estoque baixo: ${baixo.map((m) => m['nome']).join(', ')}.';
      }
      return 'Consigo responder sobre produção, custo por m³, manutenções, lucro de viagens e estoque. Tente uma dessas perguntas!';
    } catch (e) {
      return 'Tive um problema ao consultar os dados: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final m = _messages[i];
              return Align(
                alignment:
                    m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.82),
                  decoration: BoxDecoration(
                    color: m.fromUser
                        ? BrandColors.forest
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(m.fromUser ? 16 : 4),
                      bottomRight: Radius.circular(m.fromUser ? 4 : 16),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!m.fromUser) ...[
                        const Icon(Icons.auto_awesome,
                            size: 16, color: BrandColors.forest),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(m.text,
                            style: TextStyle(
                                color: m.fromUser
                                    ? Colors.white
                                    : scheme.onSurface,
                                height: 1.35)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_thinking)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Analisando dados...'),
              ],
            ),
          ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _sugestoes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ActionChip(
              label: Text(_sugestoes[i]),
              onPressed: _thinking ? null : () => _send(_sugestoes[i]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: _thinking ? null : _send,
                  decoration: const InputDecoration(
                    hintText: 'Pergunte à SILVORA IA...',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                onPressed: _thinking ? null : () => _send(_controller.text),
                mini: true,
                child: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
