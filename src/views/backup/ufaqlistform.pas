unit uFaqListForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, DBGrids, DBCtrls,
  ExtCtrls, StdCtrls, db, sqldb,
  uDBConnection,
  uFaqForm,
  uEmbeddingService,
  uFaqService;

type

  { TFaqListForm }

  TFaqListForm = class(TForm)
    btDelete: TButton;
    btnSimpan: TButton;
    btnAdd: TButton;
    Button1: TButton;
    dbmPertanyaan: TDBMemo;
    dbmReferensi: TDBMemo;
    dsFaq: TDataSource;
    EdtCari: TEdit;
    lblReferensi1: TLabel;
    Panel1: TPanel;
    Panel3: TPanel;
    qryFaq: TSQLQuery;
    dbGridFaq: TDBGrid;
    dbmJawaban: TDBMemo;
    pnlBottom: TPanel;
    pnlMain: TPanel;
    pnlRightMemo: TPanel;
    lblJawaban: TLabel;
    lblReferensi: TLabel;
    splitterVert: TSplitter;
    procedure btDeleteClick(Sender: TObject);
    procedure btnAddClick(Sender: TObject);
    procedure btnSimpanClick(Sender: TObject);
    procedure EdtCariKeyPress(Sender: TObject; var Key: char);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FFaqService : TFaqService;
    FEmbeddingService: TEmbeddingService;
    FCurrentID: Int64; // Menyimpan ID data aktif (-1 jika data baru)
    procedure RefreshGridData;
  public
  end;

var
  FaqListForm: TFaqListForm;
  DBS: TDBConnection;

implementation

{$R *.lfm}

{ TFaqListForm }

procedure TFaqListForm.FormCreate(Sender: TObject);
begin
  // 1. Instansiasi Layanan Embedding BGE-M3 (Sesuaikan IP & Port dengan server lokal Anda)
  // Menggunakan 127.0.0.1 untuk stabilitas koneksi jaringan lokal Windows
  FEmbeddingService := TEmbeddingService.Create('http://127.0.0.1:8080');

  // 2. Inisialisasi nilai awal ID aktif agar tidak membaca memori acak
  FCurrentID := -1;

  // 3. Ambil instance koneksi database singleton
  DBS := TDBConnection.GetInstance;
  DBS.Connect;

  // 4. Hubungkan kueri komponen ke database dan transaksi utama
  qryFaq.Database := DBS.Connection;
  qryFaq.Transaction := DBS.Transaction;

  // 5. Muat data ke Grid secara aman melalui prosedur penyegar
  RefreshGridData;
end;

procedure TFaqListForm.RefreshGridData;
begin
  // Memanfaatkan komponen qryFaq bawaan form (bukan FQueryList yang nil)
  qryFaq.Close;
  qryFaq.SQL.Text := 'SELECT id, tanya, jawaban, referensi FROM faq ORDER BY id DESC;';
  qryFaq.Open;

  // Konfigurasi visual kolom DBGrid setelah data berhasil dibuka
  if dbGridFaq.Columns.Count > 0 then
    dbGridFaq.Columns[0].Width := 50;   // Kolom ID
end;

procedure TFaqListForm.btnSimpanClick(Sender: TObject);
var
  VTanya, VJawaban, VReferensi: String;
  VectorJsonStr: String;
  QueryExec: TSQLQuery;
  TargetID: Int64;
begin
  VTanya := Trim(dbmPertanyaan.Text);
  VJawaban := Trim(dbmJawaban.Text);
  VReferensi := Trim(dbmReferensi.Text);

  if (VTanya = '') or (VJawaban = '') then
  begin
    ShowMessage('Kolom Pertanyaan/Kasus dan Ketentuan Hukum wajib diisi!');
    Exit;
  end;

  btnSimpan.Enabled := False;
  Application.ProcessMessages;

  QueryExec := TSQLQuery.Create(nil);
  QueryExec.DataBase := DBS.Connection;
  QueryExec.Transaction := DBS.Transaction;

  try
    try
      // Ambil nilai representasi vektor dari server lokal BGE-M3
      VectorJsonStr := FEmbeddingService.GetEmbedding(VTanya);

      Application.ProcessMessages;

      // Membuka blok transaksi database
      if not DBS.Transaction.Active then
        DBS.Transaction.StartTransaction;

      // Sinkronisasi pendeteksian ID aktif dari record grid saat ini jika mode edit
      if (FCurrentID = -1) and (not qryFaq.IsEmpty) then
        FCurrentID := qryFaq.FieldByName('id').AsLargeInt;

      if FCurrentID = -1 then
      begin
        // --- MODE SIMPAN BARU ---
        QueryExec.SQL.Text :=
          'INSERT INTO faq (tanya, jawaban, referensi) VALUES (:tanya, :jawaban, :referensi);';
        QueryExec.ParamByName('tanya').AsString := VTanya;
        QueryExec.ParamByName('jawaban').AsString := VJawaban;
        QueryExec.ParamByName('referensi').AsString := VReferensi;
        QueryExec.ExecSQL;

        QueryExec.SQL.Text := 'SELECT last_insert_rowid() AS new_id';
        QueryExec.Open;
        TargetID := QueryExec.FieldByName('new_id').AsLargeInt;
        QueryExec.Close;

        QueryExec.SQL.Text := 'INSERT INTO faq_vec (id, vektor_bge) VALUES (:id, :vector)';
        QueryExec.ParamByName('id').AsLargeInt := TargetID;
        QueryExec.ParamByName('vector').AsString := VectorJsonStr;
        QueryExec.ExecSQL;
      end
      else
      begin
        // --- MODE UPDATE / KOREKSI DATA ---
        TargetID := FCurrentID;

        QueryExec.SQL.Text :=
          'UPDATE faq SET tanya = :tanya, jawaban = :jawaban, referensi = :referensi WHERE id = :id;';
        QueryExec.ParamByName('tanya').AsString := VTanya;
        QueryExec.ParamByName('jawaban').AsString := VJawaban;
        QueryExec.ParamByName('referensi').AsString := VReferensi;
        QueryExec.ParamByName('id').AsLargeInt := TargetID;
        QueryExec.ExecSQL;

        QueryExec.SQL.Text := 'UPDATE faq_vec SET vektor_bge = :vector WHERE id = :id;';
        QueryExec.ParamByName('vector').AsString := VectorJsonStr;
        QueryExec.ParamByName('id').AsLargeInt := TargetID;
        QueryExec.ExecSQL;
      end;

      DBS.Transaction.Commit;

      ShowMessage('Status: Data & Vektor Berhasil Disinkronisasi!');

      RefreshGridData;
      FCurrentID := -1; // Kembalikan ke mode netral setelah sukses

    except
      on E: Exception do
      begin
        if DBS.Transaction.Active then
          DBS.Transaction.Rollback;

        ShowMessage('Status: Gagal sinkronisasi data!' + #13 +#13 +
                    'Terjadi kesalahan RAG Engine: ' + E.Message);
      end;
    end;
  finally
    QueryExec.Free;
    btnSimpan.Enabled := True;
    qryFaq.Close;
    qryFaq.Active:=True;

  end;
end;

procedure TFaqListForm.EdtCariKeyPress(Sender: TObject; var Key: char);
begin


if key=#13 then
begin
  qryFaq.DisableControls; // Agar DBGrid tidak berkedip parah
  try
    qryFaq.Close;
    // Gunakan klausa WHERE dan Parameter (:kriteria)
    qryFaq.SQL.Text := 'SELECT id, tanya, jawaban,referensi FROM faq WHERE jawaban LIKE :kriteria';

    // Berikan nilai parameter secara aman
    qryFaq.ParamByName('kriteria').AsString := '%' + EdtCari.Text + '%';
    qryFaq.Open;
  finally
    qryFaq.EnableControls;
  end;
end;


end;

procedure TFaqListForm.btDeleteClick(Sender: TObject);
var
  QueryExec: TSQLQuery;
begin

  if not qryFaq.Active or qryFaq.IsEmpty then
  begin
    ShowMessage('Pilih data terlebih dahulu dari tabel di sebelah kiri!');
    Exit;
  end;

  FCurrentID := qryFaq.FieldByName('id').AsLargeInt;

  if MessageDlg('Konfirmasi', 'Hapus data hukum perpajakan ini beserta index vektornya?',
    mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin

  if not DBS.Transaction.Active then
        DBS.Transaction.StartTransaction;

    QueryExec := TSQLQuery.Create(nil);
    QueryExec.DataBase := DBS.Connection;
    QueryExec.Transaction := DBS.Transaction;
    try
      try

        QueryExec.SQL.Text := 'DELETE FROM faq WHERE id = :id;';
        QueryExec.ParamByName('id').AsLargeInt := FCurrentID;
        QueryExec.ExecSQL;

        QueryExec.SQL.Text := 'DELETE FROM faq_vec WHERE id = :id;';
        QueryExec.ParamByName('id').AsLargeInt := FCurrentID;
        QueryExec.ExecSQL;

        DBS.Transaction.Commit;

        RefreshGridData;
        FCurrentID := -1;
        ShowMessage('Data sukses dihapus dari pangkalan data.');

      except
        on E: Exception do
        begin
          if DBS.Transaction.Active then
            DBS.Transaction.Rollback;
          ShowMessage('Gagal menghapus data: ' + E.Message);
        end;
      end;
    finally
      QueryExec.Free;
      qryFaq.Close;
      qryFaq.Active:=True;
    end;
  end;
end;

procedure TFaqListForm.btnAddClick(Sender: TObject);
var
  FrmFaq: TFaqForm;
begin
  FrmFaq := TFaqForm.Create(Self);
  try
    FrmFaq.ShowModal;
    RefreshGridData; // Refresh grid secara otomatis saat jendela input ditutup
  finally
    FrmFaq.Free;
  end;
end;

procedure TFaqListForm.FormDestroy(Sender: TObject);
begin
  qryFaq.Close;
  // Bersihkan memory service embedding saat form ditutup untuk mencegah memory leak
  if Assigned(FEmbeddingService) then
    FEmbeddingService.Free;
end;

procedure TFaqListForm.FormShow(Sender: TObject);
begin
  dbmJawaban.Width := Round(pnlMain.Width / 2);
end;

end.
