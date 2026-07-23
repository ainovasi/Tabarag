unit uDBTables;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqldb, uDBConnection;

type
  TDBTables = class
  public
    class procedure InitializeDatabase;
  end;

implementation

class procedure TDBTables.InitializeDatabase;
var
  DB: TDBConnection;
  Query: TSQLQuery;
begin
  DB := TDBConnection.GetInstance;
  DB.Connect;

  Query := TSQLQuery.Create(nil);
  try
    Query.Database := DB.Connection;
    Query.Transaction := DB.Transaction;

    // 1. Buat Tabel Utama FAQ
    Query.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS faq (' +
      '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      '  tanya TEXT NOT NULL,' +
      '  jawaban TEXT NOT NULL,' +
      '  referensi TEXT NOT NULL' +
      ');';
    Query.ExecSQL;

    // 2. Buat Tabel FTS5 untuk Pencarian Kata Kunci
    Query.SQL.Text :=
      'CREATE VIRTUAL TABLE IF NOT EXISTS faq_fts USING fts5(' +
      '  tanya, ' +
      '  jawaban, ' +
      '  content=''faq'',' +
      '  content_rowid=''id''' +
      ');';
    Query.ExecSQL;

    // 3. Buat Tabel Vektor untuk Semantik (1024 Dimensi)
    Query.SQL.Text :=
      'CREATE VIRTUAL TABLE IF NOT EXISTS faq_vec USING vec0(' +
      '  id INTEGER PRIMARY KEY,' +
      '  vektor_bge float[1024]' +
      ');';
    Query.ExecSQL;

    // 4. Buat Tabel Riwayat Percakapan Chat
    Query.SQL.Text :=
      'CREATE TABLE IF NOT EXISTS chat (' +
      '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      '  session_id TEXT NOT NULL,' +
      '  role TEXT CHECK(role IN (''user'', ''assistant'')) NOT NULL,' +
      '  content TEXT NOT NULL,' +
      '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
      ');';
    Query.ExecSQL;

    // 5. Buat Trigger Sinkronisasi Otomatis FTS5 (INSERT)
    Query.SQL.Text :=
      'CREATE TRIGGER IF NOT EXISTS faq_ai AFTER INSERT ON faq BEGIN ' +
      '  INSERT INTO faq_fts(rowid, tanya, jawaban) VALUES (new.id, new.tanya, new.jawaban); ' +
      'END;';
    Query.ExecSQL;

    // 6. Buat Trigger Sinkronisasi Otomatis FTS5 (DELETE)
    Query.SQL.Text :=
      'CREATE TRIGGER IF NOT EXISTS faq_ad AFTER DELETE ON faq BEGIN ' +
      '  INSERT INTO faq_fts(faq_fts, rowid, tanya, jawaban) VALUES(''delete'', old.id, old.tanya, old.jawaban); ' +
      'END;';
    Query.ExecSQL;

    // 7. Buat Trigger Sinkronisasi Otomatis FTS5 (UPDATE)
    Query.SQL.Text :=
      'CREATE TRIGGER IF NOT EXISTS faq_au AFTER UPDATE ON faq BEGIN ' +
      '  INSERT INTO faq_fts(faq_fts, rowid, tanya, jawaban) VALUES(''delete'', old.id, old.tanya, old.jawaban); ' +
      '  INSERT INTO faq_fts(rowid, tanya, jawaban) VALUES (new.id, new.tanya, new.jawaban); ' +
      'END;';
    Query.ExecSQL;

    DB.Transaction.Commit;
  except
    on E: Exception do
    begin
      DB.Transaction.Rollback;
      raise Exception.Create('Gagal melakukan inisialisasi tabel database: ' + E.Message);
    end;
  end;

 Query.Free;

end;

end.
