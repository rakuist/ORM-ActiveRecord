
unit class ORM::ActiveRecord::DB;

use JSON::Tiny;
use DBIish;

class DB is export {
  has Str $!database;
  has Str $!user;
  has Str $!password;

  has $!db;
  has @!rows;

  submethod BUILD {
    self.get-config;
    self.connect-db;
  }

  method build-insert(:$table, :%attrs) {
    my $fields = %attrs.keys.join(',');
    my $values = %attrs.values.map({ "'$_'" }).join(',');

    qq:to/SQL/;
      INSERT INTO $table ($fields)
      VALUES ($values)
    SQL
  }

  method build-select(:@fields, :$table, :%where, :@order, :$limit) {
    my $select = @fields.join(',');
    my $where = self.build-where(%where);
    my $order = @order ?? "ORDER BY @order.join(',')" !! '';
    my $limit_ = $limit ?? "LIMIT $limit" !! '';

    qq:to/SQL/;
      SELECT $select
	    FROM $table
	    WHERE $where
      $order
      $limit_
    SQL
  }

  method build-where(%where) {
    my @where;
    for %where.kv -> $k, $v {
      @where.push: "$k = '$v'";
    }

    @where.join(' AND ');
  }

  method get-objects(:$class, :@fields, :$table, :%where) {
    my @records = self.get-records(:@fields, :$table, :%where);
    my @objects;

    for @records.kv -> $k, $record {
      my $obj = $class.new(id => $record{'id'}, record => { attributes => $record, :@fields });
      @objects.push: $obj;
    }

    @objects;
  }

  method get-object(:$class, :@fields, :$table, :%where) {
    my $record = self.get-record(:@fields, :$table, :%where);
    $class.new(id => $record{'id'}, record => { attributes => $record, :@fields });
  }

  method create-object($obj) {
    my $table = $obj.WHAT.perl.lc ~ 's';
    my %attrs = $obj.attributes;
    my $sql = self.build-insert(:$table, :%attrs);

    my $query = $!db.prepare(qq:to/SQL/);
      $sql
    SQL

    my @res = $query.execute();
    @res[0][0].Int;
  }

  method get-rows(:$sql) {
    my $query = $!db.prepare(qq:to/SQL/);
      $sql
    SQL

    $query.execute();
    return $query.allrows();
  }

  method get-records(:@fields, :$table, :%where) {
    my @records;
    my $sql = self.build-select(:@fields, :$table, :%where);

    for self.get-rows(:$sql).kv -> $k, $row {
      my %record;
      for @fields.kv -> $kk, $field {
        %record{@fields[$kk]} = $row[$kk];
      }

      @records.push: %record
    }

    @records;
  }

  method get-record(:@fields, :$table, :%where) {
    my $sql = self.build-select(:@fields, :$table, :%where, limit => 1);
    my $row = self.get-rows(:$sql)[0];
    my %record;

    for @fields.kv -> $k, $field {
      %record{@fields[$k]} = $row[$k];
    }

    return %record;
  }

  method get-fields(:$table) {
    my $sql = self.build-select(
      fields => qw<column_name>.words,
      table => 'information_schema.columns',
      where => {
        'table_schema' => 'public',
        'table_name'   => $table
      },
      order => qw<table_name>.words
    );

    self.get-list(:$sql);
  }

  method get-list(:$sql, :$col=0) {
    my @list;
    my @rows = self.get-rows(:$sql);

    if @rows.elems > 0 {
      for @rows -> $row {
        @list.push: $row[$col];
      }
    }

    return @list;
  }

  method get-table-names {
    my $sql = $!db.build-select(
      fields => qw<table_name>.words,
      table  => 'information_schema.tables',
      where  => { 'table_schema' => 'public' },
      order  => qw<table_name>.word
    );

    $!db.get-list(:$sql);
  }

  method connect-db {
    return if $!db.defined;
    $!db = DBIish.connect('Pg', :$!database, :$!user, :$!password);
  }

  method get-config {
    if (my $fh = open 'config/application.json', :r) {
      my $contents = $fh.slurp-rest;
      $fh.close;

      my $json = from-json($contents);
      $!database = $json{'db'}{'name'};
      $!user     = $json{'db'}{'user'};
      $!password = $json{'db'}{'password'};
    }
  }
}
