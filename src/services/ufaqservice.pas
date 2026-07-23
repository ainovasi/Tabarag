unit uFaqService;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, sqldb, contnrs, uDBConnection, uFaqModel, uEmbeddingService,Clipbrd;

type
  TFaqService = class
  public
    function AddFaq(const ATanya, AJawaban, AReferensi: String; AEmbeddingService: TEmbeddingService): Boolean;
    function DeleteFaq(AId: Integer): Boolean;
    function RebuildAllEmbeddings(AEmbeddingService: TEmbeddingService): Boolean;
    function UpdateFaq(AId: Integer; const ATanya, AJawaban, AReferensi: String; AEmbeddingService: TEmbeddingService): Boolean;
    function HybridSearch(  const AQuery: String;   AEmbedService: TEmbeddingService;  ALimit: Integer  ): TFPObjectList;
end;

implementation

function TFaqService.AddFaq(const ATanya, AJawaban, AReferensi: String; AEmbeddingService: TEmbeddingService): Boolean;
var
  DB: TDBConnection;
  Query: TSQLQuery;
  LastId: Integer;
  EmbeddingJson: String;
begin
  Result := False;
  if (ATanya = '') or (AJawaban = '') or (AEmbeddingService = nil) then Exit;

  DB := TDBConnection.GetInstance;
  DB.Connect;

  Query := TSQLQuery.Create(nil);
  try
    Query.Database := DB.Connection;
    Query.Transaction := DB.Transaction;

    // 1. Dapatkan Vektor dari Llama Server Terlebih Dahulu
    EmbeddingJson := AEmbeddingService.GetEmbedding(ATanya);
    if EmbeddingJson = '' then raise Exception.Create('Gagal mendapatkan embedding dari server.');

    // 2. Insert ke Tabel Utama (Trigger otomatis mengisi FTS5)
    Query.SQL.Text := 'INSERT INTO faq (tanya, jawaban, referensi) VALUES (:tanya, :jawaban, :referensi);';
    Query.ParamByName('tanya').AsString := ATanya;
    Query.ParamByName('jawaban').AsString := AJawaban;
    Query.ParamByName('referensi').AsString := AReferensi;
    Query.ExecSQL;

    // 3. Ambil ID Terakhir
    Query.SQL.Text := 'SELECT last_insert_rowid();';
    Query.Open;
    LastId := Query.Fields[0].AsInteger;
    Query.Close;

    // 4. Insert Vektor ke Tabel faq_vec
    Query.SQL.Text := 'INSERT INTO faq_vec (id, vektor_bge) VALUES (:id, :vektor);';
    Query.ParamByName('id').AsInteger := LastId;
    Query.ParamByName('vektor').AsString := EmbeddingJson;
    Query.ExecSQL;


    DB.Transaction.Commit;
    Result := True;
  except
    on E: Exception do
    begin
      DB.Transaction.Rollback;
      raise Exception.Create('Gagal menyimpan FAQ: ' + E.Message);
    end;
  end;

    Query.Free;

end;

function TFaqService.DeleteFaq(AId: Integer): Boolean;
var
  DB: TDBConnection;
  Query: TSQLQuery;
begin
  Result := False;
  if AId <= 0 then Exit;

  DB := TDBConnection.GetInstance;
  DB.Connect;

  Query := TSQLQuery.Create(nil);
  try
    Query.Database := DB.Connection;
    Query.Transaction := DB.Transaction;

    // 1. Hapus data vektor terlebih dahulu di tabel faq_vec
    Query.SQL.Text := 'DELETE FROM faq_vec WHERE id = :id;';
    Query.ParamByName('id').AsInteger := AId;
    Query.ExecSQL;

    // 2. Hapus data utama di tabel faq
    // (Jika Anda menggunakan FTS5 dengan trigger, teks pencarian FTS5 juga akan otomatis terhapus)
    Query.SQL.Text := 'DELETE FROM faq WHERE id = :id;';
    Query.ParamByName('id').AsInteger := AId;
    Query.ExecSQL;

    // Komit transaksi untuk memastikan kedua tabel terhapus bersamaan
    DB.Transaction.Commit;
    Result := True;
  except
    on E: Exception do
    begin
      DB.Transaction.Rollback;
      raise Exception.Create('Gagal menghapus data FAQ & Vektor: ' + E.Message);
    end;
  end;
    Query.Free;
end;

function TFaqService.RebuildAllEmbeddings(AEmbeddingService: TEmbeddingService): Boolean;
var
  DB: TDBConnection;
  QueryRead, QueryUpdate: TSQLQuery;
  FaqId: Integer;
  TanyaText, EmbeddingJson: String;
begin
  Result := False;
  if AEmbeddingService = nil then Exit;

  DB := TDBConnection.GetInstance;
  DB.Connect;

  QueryRead := TSQLQuery.Create(nil);
  QueryUpdate := TSQLQuery.Create(nil);
  try
    QueryRead.Database := DB.Connection;
    QueryRead.Transaction := DB.Transaction;
    QueryUpdate.Database := DB.Connection;
    QueryUpdate.Transaction := DB.Transaction;

    // 1. Ambil semua ID dan Pertanyaan dari database
    QueryRead.SQL.Text := 'SELECT id, tanya FROM faq;';
    QueryRead.Open;

    while not QueryRead.EOF do
    begin
      FaqId := QueryRead.FieldByName('id').AsInteger;
      TanyaText := QueryRead.FieldByName('tanya').AsString;

      // 2. Request vektor baru ke server untuk tiap baris data
      EmbeddingJson := AEmbeddingService.GetEmbedding(TanyaText);

      if EmbeddingJson <> '' then
      begin
        // 3. Masukkan atau timpa vektor di faq_vec
        QueryUpdate.SQL.Text :=
          'INSERT INTO faq_vec (id, vektor_bge) VALUES (:id, :vektor) ' +
          'ON CONFLICT(id) DO UPDATE SET vektor_bge = excluded.vektor_bge;';
        QueryUpdate.ParamByName('id').AsInteger := FaqId;
        QueryUpdate.ParamByName('vektor').AsString := EmbeddingJson;
        QueryUpdate.ExecSQL;
      end;

      QueryRead.Next;
    end;
    QueryRead.Close;

    DB.Transaction.Commit;
    Result := True;
  except
    on E: Exception do
    begin
      DB.Transaction.Rollback;
      raise Exception.Create('Gagal melakukan sinkronisasi massal vektor: ' + E.Message);
    end;
  end;
    QueryRead.Free;
    QueryUpdate.Free;
end;

function TFaqService.UpdateFaq(AId: Integer; const ATanya, AJawaban, AReferensi: String; AEmbeddingService: TEmbeddingService): Boolean;
var
  DB: TDBConnection;
  Query: TSQLQuery;
  EmbeddingJson: String;
begin
  Result := False;
  // Validasi dasar
  if (AId <= 0) or (ATanya = '') or (AJawaban = '') or (AEmbeddingService = nil) then Exit;

  DB := TDBConnection.GetInstance;
  DB.Connect;

  Query := TSQLQuery.Create(nil);
  try
    Query.Database := DB.Connection;
    Query.Transaction := DB.Transaction;

    // 1. Hitung ulang vektor baru dari Llama Server menggunakan teks pertanyaan yang baru
    EmbeddingJson := AEmbeddingService.GetEmbedding(ATanya);
    if EmbeddingJson = '' then raise Exception.Create('Gagal mendapatkan embedding baru dari server.');

    // 2. Update data tekstual di tabel utama 'faq' (FTS5 akan otomatis terupdate via trigger)
    Query.SQL.Text :=
      'UPDATE faq SET tanya = :tanya, jawaban = :jawaban, referensi = :referensi ' +
      'WHERE id = :id;';
    Query.ParamByName('tanya').AsString := ATanya;
    Query.ParamByName('jawaban').AsString := AJawaban;
    Query.ParamByName('referensi').AsString := AReferensi;
    Query.ParamByName('id').AsInteger := AId;
    Query.ExecSQL;

    // 3. Update data vektor di tabel 'faq_vec' agar pencarian semantik tetap akurat
    Query.SQL.Text :=
      'UPDATE faq_vec SET vektor_bge = :vektor ' +
      'WHERE id = :id;';
    Query.ParamByName('id').AsInteger := AId;
    Query.ParamByName('vektor').AsString := EmbeddingJson;
    Query.ExecSQL;

    // Komit transaksi jika kedua proses di atas berhasil tanpa error
    DB.Transaction.Commit;
    Result := True;
  except
    on E: Exception do
    begin
      DB.Transaction.Rollback;
      raise Exception.Create('Gagal memperbarui data FAQ & Vektor: ' + E.Message);
    end;
  end;
    Query.Free;
end;

function SanitizeFTSSelective(const AInput: String): String;
begin
  Result := AInput;
  // Hapus karakter yang merusak struktur logika kueri FTS
  Result := StringReplace(Result, '"', ' ', [rfReplaceAll]); // Double quote
  Result := StringReplace(Result, '*', ' ', [rfReplaceAll]); // Asterisk (wildcard)
  Result := StringReplace(Result, ':', ' ', [rfReplaceAll]); // Kolon (column filter)
  Result := StringReplace(Result, '-', ' ', [rfReplaceAll]); // Minus (exclusion)
  Result := StringReplace(Result, '+', ' ', [rfReplaceAll]); // Plus
  Result := StringReplace(Result, '?', ' ', [rfReplaceAll]); // Tanda tanya

  // Amankan dari SQL Injection jika ada petik tunggal tersisa
  Result := StringReplace(Result, '''', '''''', [rfReplaceAll]);

  Result := Trim(Result);
end;


function TFaqService.HybridSearch( const AQuery: String; AEmbedService: TEmbeddingService; ALimit: Integer ): TFPObjectList;
var
  Query: TSQLQuery;
  VectorJsonStr: String;
  SafeQueryText: String;
  SafeVectorText: String;

  FaqItem: TFaqSearchResult;
begin
  Result := TFPObjectList.Create(True);

  if Trim(AQuery) = '' then Exit;
  if not Assigned(AEmbedService) then Exit;

  // 1. Dapatkan representasi vektor (JSON String) dari teks kueri
  VectorJsonStr := AEmbedService.GetEmbedding(AQuery);

  // 2. Lakukan escaping tanda petik tunggal (') untuk mencegah SQL Syntax Error

  SafeQueryText := SanitizeFTSSelective(AQuery);
  SafeVectorText := VectorJsonStr; // Vektor berupa angka [0.12, -0.4, ...] tidak mengandung petik

  Clipboard.AsText:=SafeVectorText;

  Query := TSQLQuery.Create(nil);
  try
    // Sesuaikan dengan variabel objek koneksi database Anda
    Query.DataBase := TDBConnection.GetInstance.Connection;

    // KUNCI UTAMA: Matikan parser internal Lazarus agar SQL dikirim 100% utuh ke SQLite
    Query.ParseSQL := False;

    // 3. RAKIT KUERI SECARA INLINE (Bypass Bug Parser TSQLQuery)
    Query.SQL.Text :=
      'WITH fts_results AS ( ' +
      '  SELECT rowid as id, ROW_NUMBER() OVER (ORDER BY bm25(faq_fts) ASC) as rank ' +
      '  FROM faq_fts WHERE faq_fts MATCH ''' + SafeQueryText + ''' ' +
      '), ' +
      'vec_results AS ( ' +
      '  SELECT id, ROW_NUMBER() OVER (ORDER BY vec_distance_cosine(vektor_bge, ''' + SafeVectorText + ''') ASC) as rank ' +
      '  FROM faq_vec WHERE vektor_bge MATCH ''' + SafeVectorText + ''' AND k = 20 ' +
      ') ' +
      'SELECT f.id, f.tanya, f.jawaban, f.referensi, ' +
      '       COALESCE(1.0 / (60 + fts.rank), 0.0) + COALESCE(1.0 / (60 + vec.rank), 0.0) as rrf_score ' +
      'FROM faq f ' +
      ' JOIN fts_results fts ON f.id = fts.id ' +
      ' JOIN vec_results vec ON f.id = vec.id ' +
      'WHERE fts.id IS NOT NULL OR vec.id IS NOT NULL ' +
      'ORDER BY rrf_score DESC LIMIT ' + IntToStr(ALimit) + ';';

    // 4. Buka kursor (Tidak perlu lagi memanggil Query.ParamByName)
    Query.Open;

    // 5. Pindahkan data hasil filter murni SQLite ke Object List
    while not Query.EOF do
    begin
      FaqItem := TFaqSearchResult.Create;
      try
        FaqItem.Id := Query.FieldByName('id').AsInteger;
        FaqItem.Tanya := Query.FieldByName('tanya').AsString;
        FaqItem.Jawaban := Query.FieldByName('jawaban').AsString;
        FaqItem.Referensi := Query.FieldByName('referensi').AsString;
        Result.Add(FaqItem);
      except
        FaqItem.Free;
        raise;
      end;
      Query.Next;
    end;

    Query.Close;
  finally
    Query.Free;
  end;
end;

end.
