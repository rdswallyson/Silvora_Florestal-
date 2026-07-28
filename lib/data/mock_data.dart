import 'package:flutter/material.dart';

/// Dados de exemplo (mock) para o protótipo. Sem backend.

class Funcionario {
  final String nome;
  final String cargo;
  final String telefone;
  final String situacao;
  final String iniciais;
  const Funcionario(this.nome, this.cargo, this.telefone, this.situacao,
      this.iniciais);
}

class Equipe {
  final String nome;
  final String lider;
  final int integrantes;
  final String caminhao;
  final String area;
  const Equipe(this.nome, this.lider, this.integrantes, this.caminhao,
      this.area);
}

class Fazenda {
  final String nome;
  final String proprietario;
  final String municipio;
  final String uf;
  final double areaHa;
  const Fazenda(
      this.nome, this.proprietario, this.municipio, this.uf, this.areaHa);
}

class Talhao {
  final String codigo;
  final String especie;
  final int idadeAnos;
  final double areaHa;
  final double volumeM3;
  final String situacao;
  const Talhao(this.codigo, this.especie, this.idadeAnos, this.areaHa,
      this.volumeM3, this.situacao);
}

class Producao {
  final String equipe;
  final String talhao;
  final String data;
  final double volumeM3;
  final int arvores;
  const Producao(
      this.equipe, this.talhao, this.data, this.volumeM3, this.arvores);
}

class Cliente {
  final String nome;
  final String tipo;
  final String cidade;
  final double pendencia;
  const Cliente(this.nome, this.tipo, this.cidade, this.pendencia);
}

class Equipamento {
  final String nome;
  final String tipo;
  final int horas;
  final String situacao;
  const Equipamento(this.nome, this.tipo, this.horas, this.situacao);
}

class ItemEstoque {
  final String nome;
  final int quantidade;
  final int minimo;
  final String unidade;
  const ItemEstoque(this.nome, this.quantidade, this.minimo, this.unidade);
  bool get baixo => quantidade <= minimo;
}

class Transporte {
  final String caminhao;
  final String origem;
  final String destino;
  final double volumeM3;
  final double frete;
  const Transporte(
      this.caminhao, this.origem, this.destino, this.volumeM3, this.frete);
}

class Alerta {
  final IconData icon;
  final String titulo;
  final String descricao;
  final Color cor;
  const Alerta(this.icon, this.titulo, this.descricao, this.cor);
}

class MockData {
  static const funcionarios = <Funcionario>[
    Funcionario('João Pereira', 'Gerente', '(66) 99988-1122', 'Ativo', 'JP'),
    Funcionario('Carlos Souza', 'Motosserrista', '(66) 99871-3344', 'Ativo', 'CS'),
    Funcionario('Ana Lima', 'Supervisora', '(66) 99760-5566', 'Ativo', 'AL'),
    Funcionario('Marcos Dias', 'Motorista', '(66) 99655-7788', 'Ativo', 'MD'),
    Funcionario('Rafael Alves', 'Ajudante', '(66) 99544-9900', 'Férias', 'RA'),
    Funcionario('Pedro Rocha', 'Operador', '(66) 99433-2211', 'Ativo', 'PR'),
  ];

  static const equipes = <Equipe>[
    Equipe('Equipe Alpha', 'Carlos Souza', 5, 'MB-2226 / KLM-1A23', 'Faz. Boa Vista'),
    Equipe('Equipe Bravo', 'Ana Lima', 4, 'Volvo VM / KLR-5C67', 'Faz. Santa Rita'),
    Equipe('Equipe Charlie', 'Pedro Rocha', 6, 'Scania P360 / KMN-8D90', 'Faz. Três Rios'),
  ];

  static const fazendas = <Fazenda>[
    Fazenda('Boa Vista', 'Agro Silva Ltda', 'Sinop', 'MT', 1240),
    Fazenda('Santa Rita', 'José Andrade', 'Sorriso', 'MT', 860),
    Fazenda('Três Rios', 'Reflora S/A', 'Lucas do Rio Verde', 'MT', 2100),
  ];

  static const talhoes = <Talhao>[
    Talhao('T-01', 'Eucalipto', 7, 42.5, 6800, 'Pronto p/ corte'),
    Talhao('T-02', 'Eucalipto', 5, 38.0, 4200, 'Em crescimento'),
    Talhao('T-03', 'Pinus', 9, 55.2, 9100, 'Em corte'),
    Talhao('T-04', 'Eucalipto', 3, 27.4, 1800, 'Em crescimento'),
  ];

  static const producoes = <Producao>[
    Producao('Equipe Alpha', 'T-01', 'Hoje 07:00–11:30', 62.5, 410),
    Producao('Equipe Charlie', 'T-03', 'Hoje 07:20–12:00', 78.0, 520),
    Producao('Equipe Bravo', 'T-02', 'Ontem', 54.2, 360),
    Producao('Equipe Alpha', 'T-01', 'Ontem', 60.1, 395),
  ];

  static const clientes = <Cliente>[
    Cliente('Cerâmica Vale Verde', 'Cerâmica', 'Sinop/MT', 12500),
    Cliente('Olaria São Pedro', 'Olaria', 'Sorriso/MT', 0),
    Cliente('Indústria Madenorte', 'Indústria', 'Cuiabá/MT', 4800),
    Cliente('Produtor R. Menezes', 'Produtor', 'Nova Mutum/MT', 0),
  ];

  static const equipamentos = <Equipamento>[
    Equipamento('Motosserra Stihl MS 660', 'Motosserra', 1240, 'Operando'),
    Equipamento('Motosserra Husqvarna 372', 'Motosserra', 980, 'Manutenção'),
    Equipamento('Trator Florestal JD', 'Máquina', 3200, 'Operando'),
    Equipamento('Motosserra Stihl MS 382', 'Motosserra', 610, 'Operando'),
  ];

  static const estoque = <ItemEstoque>[
    ItemEstoque('Corrente 3/8"', 22, 10, 'un'),
    ItemEstoque('Sabre 25"', 4, 6, 'un'),
    ItemEstoque('Óleo 2T', 38, 15, 'L'),
    ItemEstoque('Diesel', 320, 200, 'L'),
    ItemEstoque('Lima 5.5mm', 5, 12, 'un'),
    ItemEstoque('Luvas EPI', 48, 20, 'par'),
  ];

  static const transportes = <Transporte>[
    Transporte('Scania P360', 'Faz. Três Rios', 'Cerâmica Vale Verde', 32.0, 1850),
    Transporte('Volvo VM', 'Faz. Santa Rita', 'Madenorte', 28.5, 1620),
    Transporte('MB 2226', 'Faz. Boa Vista', 'Olaria São Pedro', 30.0, 1700),
  ];

  static const alertas = <Alerta>[
    Alerta(Icons.build_circle_outlined, 'Manutenção preventiva',
        'Motosserra Husqvarna 372 atingiu 1000h', Color(0xFFF57C00)),
    Alerta(Icons.inventory_2_outlined, 'Estoque baixo',
        'Sabre 25" abaixo do mínimo (4/6)', Color(0xFFD32F2F)),
    Alerta(Icons.description_outlined, 'Documento vencendo',
        'CNH do motorista Marcos vence em 12 dias', Color(0xFF1976D2)),
    Alerta(Icons.trending_down, 'Produção abaixo da meta',
        'Equipe Bravo 12% abaixo da meta semanal', Color(0xFFF57C00)),
  ];

  static const notificacoes = alertas;
}
