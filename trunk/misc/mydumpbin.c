/*
 * cheap dumpbin clone
 *
 * Reference:
 * http://msdn.microsoft.com/msdnmag/issues/02/03/PE2/default.aspx
 * http://forums.belution.com/ja/vc/000/234/78s.shtml
 * http://nienie.com/~masapico/api_ImageDirectoryEntryToData.html
 * http://www.geocities.jp/i96815/windows/win09.html
 */

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define TO_DOS_HEADER(base) ((PIMAGE_DOS_HEADER)(base))
#define TO_NT_HEADERS(base) ((PIMAGE_NT_HEADERS)((LPBYTE)(base) + TO_DOS_HEADER(base)->e_lfanew))

/* VC8/include/delayimp.h */
#if !defined(_DELAY_IMP_VER)
typedef DWORD                       RVA;

typedef struct ImgDelayDescr {
    DWORD           grAttrs;        // attributes
    RVA             rvaDLLName;     // RVA to dll name
    RVA             rvaHmod;        // RVA of module handle
    RVA             rvaIAT;         // RVA of the IAT
    RVA             rvaINT;         // RVA of the INT
    RVA             rvaBoundIAT;    // RVA of the optional bound IAT
    RVA             rvaUnloadIAT;   // RVA of optional copy of original IAT
    DWORD           dwTimeStamp;    // 0 if not bound,
                                    // O.W. date/time stamp of DLL bound to (Old BIND)
    } ImgDelayDescr, * PImgDelayDescr;

enum DLAttr {                   // Delay Load Attributes
    dlattrRva = 0x1,                // RVAs are used instead of pointers
                                    // Having this set indicates a VC7.0
                                    // and above delay load descriptor.
    };
#endif

static PVOID MyImageDirectoryEntryToData(LPVOID Base, BOOLEAN MappedAsImage, USHORT DirectoryEntry, PULONG Size);
static DWORD load_module(const char *modulepath);
static void dump_dependents(DWORD Base);
static void dump_imports(DWORD Base);
static void dump_bound_imports(DWORD Base);
static void dump_delay_imports(DWORD Base);
static void dump_exports(DWORD Base);

/*
 * The formal way is
 *   imagehlp.h or dbghelp.h
 *   imagehlp.lib or dbghelp.lib
 *   ImageDirectoryEntryToData()
 *
 * Size is whole data size (including dll name buffer, for example). It is not
 * size of result pointer.
 * If result is array, last one is zero filled as sentinel.
 */
static PVOID
MyImageDirectoryEntryToData(LPVOID Base, BOOLEAN MappedAsImage, USHORT DirectoryEntry, PULONG Size)
{
  /* TODO: MappedAsImage? */
  PIMAGE_DATA_DIRECTORY p;
  p = TO_NT_HEADERS(Base)->OptionalHeader.DataDirectory + DirectoryEntry;
  if (p->VirtualAddress == 0) {
    *Size = 0;
    return NULL;
  }
  *Size = p->Size;
  return (PVOID)((LPBYTE)Base + p->VirtualAddress);
}

static DWORD
load_module(const char *modulepath)
{
  DWORD Base;

  printf("Dump of file %s\n", modulepath);
  printf("\n");

  Base = (DWORD)LoadLibrary(modulepath);
  if (Base == 0) {
    printf("fatal error: cannot open '%s'\n", modulepath);
    exit(1);
  }

  if (TO_NT_HEADERS(Base)->FileHeader.Characteristics & IMAGE_FILE_DLL)
    printf("File Type: DLL\n");
  else
    printf("File Type: EXECUTABLE IMAGE\n");
  printf("\n");

  return Base;
}

static void
dump_dependents(DWORD Base)
{
  ULONG Size;
  PIMAGE_IMPORT_DESCRIPTOR Imp;

  Imp = MyImageDirectoryEntryToData(
      (LPVOID)Base,
      TRUE,
      IMAGE_DIRECTORY_ENTRY_IMPORT,
      &Size);
  if (Imp == NULL)
    return;

  printf("  Image has the following dependencies:\n");
  printf("\n");
  for ( ; Imp->OriginalFirstThunk != 0; ++Imp)
    printf("    %s\n", Base + Imp->Name);
  printf("\n");
}

static void
dump_imports(DWORD Base)
{
  ULONG Size;
  PIMAGE_IMPORT_DESCRIPTOR Imp;
  PIMAGE_THUNK_DATA Name;         /* Import Name Table */
  PIMAGE_THUNK_DATA Addr;         /* Import Address Table */
  PIMAGE_IMPORT_BY_NAME ImpName;

  Imp = MyImageDirectoryEntryToData(
      (LPVOID)Base,
      TRUE,
      IMAGE_DIRECTORY_ENTRY_IMPORT,
      &Size);
  if (Imp == NULL)
    return;

  printf("  Section contains the following imports:\n");
  printf("\n");
  for ( ; Imp->OriginalFirstThunk != 0; ++Imp) {
    Addr = (PIMAGE_THUNK_DATA)(Base + Imp->FirstThunk);
    Name = (PIMAGE_THUNK_DATA)(Base + Imp->OriginalFirstThunk);
    printf("    %s\n", Base + Imp->Name);
    printf("              %08X Import Address Table\n", Addr);
    printf("              %08X Import Name Table\n", Name);
    printf("              %8X time date stamp\n", Imp->TimeDateStamp);
    printf("              %08X Index of first forwarder reference\n", Imp->ForwarderChain);
    printf("\n");
    for ( ; Addr->u1.Function != 0; ++Addr, ++Name) {
      if (IMAGE_SNAP_BY_ORDINAL(Name->u1.Ordinal)) {
        printf("      %08X        Ordinal   %d\n", Addr->u1.Function, IMAGE_ORDINAL(Name->u1.Ordinal));
      } else {
        ImpName = (PIMAGE_IMPORT_BY_NAME)(Base + Name->u1.AddressOfData);
        printf("      %08X %6X %s\n", Addr->u1.Function, ImpName->Hint, ImpName->Name);
      }
    }
    printf("\n");
  }
}

static void
dump_bound_imports(DWORD Base)
{
  ULONG Size;
  PIMAGE_BOUND_IMPORT_DESCRIPTOR BoundBase;
  PIMAGE_BOUND_IMPORT_DESCRIPTOR Bound;
  int i;

  BoundBase = MyImageDirectoryEntryToData(
      (LPVOID)Base,
      TRUE,
      IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT,
      &Size);
  if (BoundBase == NULL)
    return;

  printf("Header contains the following bound import information:\n");
  for (Bound = BoundBase ; Bound->TimeDateStamp != 0; ++Bound) {
    printf("    Bound to %s [%8X] %s",
        (LPBYTE)BoundBase + Bound->OffsetModuleName,
        Bound->TimeDateStamp,
        ctime((time_t *)&Bound->TimeDateStamp));
    if (Bound->NumberOfModuleForwarderRefs != 0) {
      for (i = Bound->NumberOfModuleForwarderRefs; i != 0; --i) {
        ++Bound;
        printf("      Contained forwarders bound to %s [%8X] %s",
            (LPBYTE)BoundBase + Bound->OffsetModuleName,
            Bound->TimeDateStamp,
            ctime((time_t *)&Bound->TimeDateStamp));
      }
    }
  }
  printf("\n");
}

static void
dump_delay_imports(DWORD Base)
{
  ULONG Size;
  PImgDelayDescr Delay;
  PIMAGE_THUNK_DATA Name;         /* Import Name Table */
  PIMAGE_THUNK_DATA Addr;         /* Import Address Table */
  PIMAGE_IMPORT_BY_NAME ImpName;

  Delay = MyImageDirectoryEntryToData(
      (LPVOID)Base,
      TRUE,
      IMAGE_DIRECTORY_ENTRY_DELAY_IMPORT,
      &Size);
  if (Delay == NULL)
    return;

  printf("Section contains the following delay load imports:\n");
  printf("\n");
  for ( ; Delay->rvaHmod != 0; ++Delay) {
    printf("    %s\n", Base + Delay->rvaDLLName);
    printf("              %08X Characteristics\n", Delay->grAttrs);
    printf("              %08X Address of HMODULE\n", Base + Delay->rvaHmod);
    printf("              %08X Import Address Table\n", Base + Delay->rvaIAT);
    printf("              %08X Import Name Table\n", Base + Delay->rvaINT);
    printf("              %08X Bound Import Name Table\n",
        (Delay->rvaBoundIAT == 0) ? 0 : Base + Delay->rvaBoundIAT);
    printf("              %08X Unload Import Name Table\n",
        (Delay->rvaUnloadIAT == 0) ? 0 : Base + Delay->rvaUnloadIAT);
    printf("              %8X time date stamp\n", Delay->dwTimeStamp);
    printf("\n");
    Addr = (PIMAGE_THUNK_DATA)(Base + Delay->rvaIAT);
    Name = (PIMAGE_THUNK_DATA)(Base + Delay->rvaINT);
    for ( ; Addr->u1.Function != 0; ++Addr, ++Name) {
      if (IMAGE_SNAP_BY_ORDINAL(Name->u1.Ordinal)) {
        printf("          %08X                 Ordinal   %d\n", Addr->u1.Function, IMAGE_ORDINAL(Name->u1.Ordinal));
      } else {
        ImpName = (PIMAGE_IMPORT_BY_NAME)(Base + Name->u1.AddressOfData);
        printf("          %08X        %8X %s\n", Addr->u1.Function, ImpName->Hint, ImpName->Name);
      }
    }
    printf("\n");
  }
  printf("\n");
}

static void
dump_exports(DWORD Base)
{
  ULONG Size;
  PIMAGE_EXPORT_DIRECTORY Exp;
  WORD *Ordinal;
  DWORD *Addr;
  DWORD *Name;
  DWORD hint;
  char buf[32];

  Exp = MyImageDirectoryEntryToData(
      (LPVOID)Base,
      TRUE,
      IMAGE_DIRECTORY_ENTRY_EXPORT,
      &Size);
  if (Exp == NULL)
    return;

  printf("  Section contains the following exports for %s\n", Base + Exp->Name);
  printf("\n");
  printf("    %08X characteristics\n", Exp->Characteristics);
  printf("    %8X time date stamp %s", Exp->TimeDateStamp, ctime((time_t *)(&Exp->TimeDateStamp)));
  sprintf(buf, "%d.%02d", Exp->MajorVersion, Exp->MinorVersion);
  printf("    %8s version\n", buf);
  printf("    %8d ordinal base\n", Exp->Base);
  printf("    %8d number of functions\n", Exp->NumberOfFunctions);
  printf("    %8d number of names\n", Exp->NumberOfNames);
  printf("\n");
  printf("    ordinal hint RVA      name\n");
  printf("\n");
  Ordinal = (WORD *)(Base + Exp->AddressOfNameOrdinals);
  Addr = (DWORD *)(Base + Exp->AddressOfFunctions);
  Name = (DWORD *)(Base + Exp->AddressOfNames);
  for (hint = 0; hint < Exp->NumberOfNames; ++hint) {
    printf("    %7d %4X %08X %s\n",
        Exp->Base + Ordinal[hint],
        hint,
        Addr[Ordinal[hint]],
        Base + Name[hint]);
  }
}

int
main(int argc, char **argv)
{
  DWORD Base;
  if (argc == 3 && stricmp(argv[1] + 1, "DEPENDENTS") == 0) {
    Base = load_module(argv[2]);
    dump_dependents(Base);
  } else if (argc == 3 && stricmp(argv[1] + 1, "EXPORTS") == 0) {
    Base = load_module(argv[2]);
    dump_exports(Base);
  } else if (argc == 3 && stricmp(argv[1] + 1, "IMPORTS") == 0) {
    Base = load_module(argv[2]);
    dump_imports(Base);
    dump_bound_imports(Base);
    dump_delay_imports(Base);
  } else {
    printf("usage: %s [option] [file]\n", argv[0]);
    printf("\n");
    printf("      /DEPENDENTS\n");
    printf("      /EXPORTS\n");
    printf("      /IMPORTS\n");
  }
  return 0;
}