/* workaround for
 * http://sourceforge.net/tracker/index.php?func=detail&aid=3495304&group_id=2435&atid=302435
 */
#include <sys/stat.h>
#ifndef	_NO_OLDNAMES
#ifndef _USE_32BIT_TIME_T
  _CRTALIAS int __cdecl __MINGW_NOTHROW	fstat (int _v1, struct stat* _v2)		 { typedef int __assert_same_size[sizeof(struct _stat64i32) == sizeof(struct stat)?1:-1]; return(_fstat64i32 (_v1,(struct _stat64i32*)_v2)); }
_CRTALIAS int __cdecl __MINGW_NOTHROW	stat (const char* _v1, struct stat* _v2)	 { typedef int __assert_same_size[sizeof(struct _stat64i32) == sizeof(struct stat)?1:-1]; return(_stat64i32  (_v1,(struct _stat64i32*)_v2)); }
#else
_CRTALIAS int __cdecl __MINGW_NOTHROW	fstat (int _v1, struct stat* _v2)		 { typedef int __assert_same_size[sizeof(struct __stat32) == sizeof(struct stat)?1:-1]; return(_fstat32 (_v1,(struct __stat32*)_v2)); }
_CRTALIAS int __cdecl __MINGW_NOTHROW	stat (const char* _v1, struct stat* _v2)	 { typedef int __assert_same_size[sizeof(struct __stat32) == sizeof(struct stat)?1:-1]; return(_stat32  (_v1,(struct __stat32*)_v2)); }
#endif /* !_USE_32BIT_TIME_T */
#endif	/* Not _NO_OLDNAMES */
