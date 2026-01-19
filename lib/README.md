# Estrutura do Projeto - Clean Architecture

Este projeto segue os princípios da Clean Architecture, organizando o código em módulos e camadas bem definidas.

## Estrutura de Pastas

```
lib/
├── core/                    # Código compartilhado entre features
│   ├── routes/              # Configuração de rotas
│   ├── theme/               # Configuração de temas
│   └── widgets/             # Widgets reutilizáveis
│
├── features/                # Módulos de features
│   ├── home/                # Feature Home
│   │   ├── data/            # Camada de dados
│   │   ├── domain/          # Camada de domínio
│   │   └── presentation/   # Camada de apresentação
│   │       └── pages/       # Páginas da feature
│   │
│   ├── tela1/               # Feature Tela 1
│   │   └── presentation/
│   │       └── pages/
│   │
│   ├── tela2/               # Feature Tela 2
│   │   └── presentation/
│   │       └── pages/
│   │
│   └── tela3/               # Feature Tela 3
│       └── presentation/
│           └── pages/
│
└── main.dart                # Ponto de entrada da aplicação
```

## Camadas da Clean Architecture

### 1. Presentation Layer
- **Responsabilidade**: Interface do usuário, widgets, páginas
- **Localização**: `features/[feature]/presentation/`
- **Estrutura**:
  - `pages/`: Páginas da feature
  - `widgets/`: Widgets específicos da feature
  - `controllers/` ou `blocs/`: Lógica de apresentação (se necessário)

### 2. Domain Layer
- **Responsabilidade**: Lógica de negócio pura, independente de frameworks
- **Localização**: `features/[feature]/domain/`
- **Estrutura**:
  - `entities/`: Entidades de domínio
  - `repositories/`: Interfaces de repositórios
  - `use_cases/`: Casos de uso

### 3. Data Layer
- **Responsabilidade**: Implementação de repositórios e fontes de dados
- **Localização**: `features/[feature]/data/`
- **Estrutura**:
  - `repositories/`: Implementação dos repositórios
  - `data_sources/`: Fontes de dados (API, Local Storage)
  - `models/`: Modelos de dados

## Core

O diretório `core/` contém código compartilhado entre todas as features:

- **routes/**: Configuração centralizada de rotas
- **theme/**: Configuração de temas da aplicação
- **widgets/**: Widgets reutilizáveis em toda a aplicação

## Como Adicionar uma Nova Feature

1. Crie a estrutura de pastas em `features/[nome_feature]/`
2. Crie as camadas: `presentation/`, `domain/`, `data/`
3. Adicione a rota em `core/routes/app_routes.dart`
4. Crie as páginas em `presentation/pages/`

## Exemplo de Nova Feature

```
features/
└── nova_feature/
    ├── data/
    │   ├── models/
    │   ├── repositories/
    │   └── data_sources/
    ├── domain/
    │   ├── entities/
    │   ├── repositories/
    │   └── use_cases/
    └── presentation/
        ├── pages/
        └── widgets/
```

