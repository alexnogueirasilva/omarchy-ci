# CI

Plugin da barra do Omarchy para GitHub Actions. O ícone é o octocat. Um ponto aparece quando algum check falhou, e uma barra anda enquanto uma run está em progresso.

O painel lista a última run de cada workflow em cada branch. Uma falha fica visível enquanto essa linha continua aberta e o check segue vermelho. Ela sai da lista quando uma run mais nova passa, quando o pull request é mergeado ou fechado, ou quando o job é um update solto do Dependabot sem pull request aberto. O erro da run pode ser copiado, e a run abre no GitHub.

O plugin usa o `gh` que já está autenticado na máquina. Não guarda token.

## Instalar

```sh
omarchy plugin add https://github.com/alexnogueirasilva/omarchy-ci.git --enable
```

Precisa de `python3`, `gh` e `wl-copy`.

## Repositórios

A lista acompanhada está em `bin/ci.py`, na constante `REPOS`. O título do painel está em `Panel.qml`.

## Remover

```sh
omarchy plugin remove alex.ci
```
