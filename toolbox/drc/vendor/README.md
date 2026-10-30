# PDF runtime

The Capture helper embeds PdfPig 0.1.9 for .NET Framework 4.7.1 and its dependencies.
The deployed plugin needs no Python installation. `build.py` verifies every DLL
against `runtime-sha256.json` before embedding it.

Pinned NuGet packages, downloaded from `https://api.nuget.org/v3-flatcontainer/`:

| Package | Version | Package SHA256 |
|---|---|---|
| PdfPig | 0.1.9 | 00f0126ba87c4743fffabaf313052b50b8b4991572d72ac19764fbf596140f5a |
| Microsoft.Bcl.HashCode | 1.1.1 | 80fe99844b238db9b0e9ae3beec9bb52e3af185153c5961f444da42b12bc8e77 |
| System.Memory | 4.5.5 | 10f43da352a29fb2b3188e4edd4dcf5100194c8b526e4f61fe2e2b5623775a22 |
| System.Buffers | 4.5.1 | c30b3dd2c7e2f4cee4b823d692fd42118309b42ab1f5007f923d329a5b0d6b12 |
| System.Numerics.Vectors | 4.5.0 | a9d49320581fda1b4f4be6212c68c01a22cdf228026099c20a8eabefcf90f9cf |
| System.Runtime.CompilerServices.Unsafe | 4.5.3 | 96764c52a44ee1161151e48ef07489f72047a851cb55b99e9f01d6908536d1a9 |

`pdf-runtime/` contains the net471 PdfPig DLLs, net461 dependency DLLs, and
net46 System.Numerics.Vectors. Licenses and upstream notices are combined in
`THIRD-PARTY-NOTICES.txt`, also embedded in the helper as `pdf.NOTICES`.
Manufacturer PDFs are downloaded into the user's central document directory;
the installer does not redistribute the TI datasheet.
