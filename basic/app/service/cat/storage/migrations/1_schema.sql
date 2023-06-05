create table if not exists cat
(
    id    varchar(26)            not null,
    name  text                   not null,
    breed text default 'unknown' not null,
    age   int  default 1         not null,
    constraint cat_pk
        primary key (id)
);

create unique index if not exists cat_id_uindex
    on cat (id);

---- create above / drop below ----

drop table if exists cat cascade;