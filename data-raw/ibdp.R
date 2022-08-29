library(tidyverse)

arquivos <- fs::dir_ls("data-raw/pgfn")


# leitura e arrumacao -----------------------------------------------------


pgfn_raw <- map_dfr(
  arquivos,
  read_delim,
  delim = ";",
  col_types = cols(
    DATA_INSCRICAO = col_date("%d/%m/%Y"),
    VALOR_CONSOLIDADO = col_number(),
    .default = col_character()
  ),
  locale = locale(encoding = "latin1", grouping_mark = ",", decimal_mark = ".")
) |>
  janitor::clean_names()

pgfn <- pgfn_raw

readr::write_rds(pgfn, "data-raw/pgfn.rds")

# visualizacao ------------------------------------------------------------

# tabela
pgfn |>
  count(tipo_credito, sort = TRUE) |>
  mutate(prop = scales::percent(n / sum(n))) |>
  DT::datatable()

pgfn |>
  count(tipo_situacao_inscricao, sort = TRUE) |>
  mutate(prop = scales::percent(n / sum(n))) |>
  DT::datatable()

# mapa
estados <- geobr::read_state()

codigos <- estados |>
  as_tibble() |>
  select(code_state, abbrev_state)

populacao <- abjData::pnud_uf |>
  filter(ano == 2010) |>
  select(code_state = uf, popt) |>
  left_join(codigos, "code_state")


pgfn_uf <- pgfn |>
  group_by(abbrev_state = uf_unidade_responsavel) |>
  summarise(
    n = n(),
    valor = sum(valor_consolidado)
  ) |>
  left_join(populacao, "abbrev_state") |>
  mutate(
    n_pop = n / popt,
    vl_pop = valor / popt
  )

estados |>
  left_join(pgfn_uf, c("abbrev_state")) |>
  ggplot() +
  geom_sf(aes(fill = vl_pop), color = "black", size = .1) +
  scale_fill_viridis_c(
    begin = .2, end = .8,
    option = "A", trans = "log10"
  ) +
  theme_void() +
  labs(
    title = "Dívida total / população"
  )


pgfn_mes <- pgfn |>
  mutate(data = lubridate::floor_date(data_inscricao, "month")) |>
  filter(data >= "2008-01-01") |>
  count(data)

pgfn_mes |>
  ggplot(aes(x = data, y = n/1e3)) +
  geom_line(size = 1) +
  theme_minimal() +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(
    x = "Mês", y = "Quantidade (milhares)",
    title = "Quantidade de inscrições ao longo dos anos"
  )



# modelo ------------------------------------------------------------------

library(tsibble)
library(fable)


pgfn_tsibble <- pgfn_mes |>
  mutate(data = yearmonth(data), n = sqrt(n/1e3)) |>
  as_tsibble(index = data)

fit <- pgfn_tsibble |>
  model(
    model = ARIMA(n ~ pdq(2,1,2) + PDQ(1,1,1))
  )

fit |>
  forecast(h = 12) |>
  mutate(.mean = (.mean^2), n = (n^2)) |>
  autoplot(pgfn_tsibble |> mutate(n = (n^2))) +
  theme_minimal() +
  labs(
    x = "Mês",
    y = "Quantidade (milhares)",
    title = "Quantidade de inscrições ao longo dos anos"
  )


