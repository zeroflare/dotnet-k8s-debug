# 映像內建 vsdbg；PDB 不進最終映像，由 deploy 存檔、Enable 再注入（必須同源）。
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/NhiApi/NhiApi.csproj NhiApi/
RUN dotnet restore NhiApi/NhiApi.csproj

COPY src/NhiApi/ NhiApi/
WORKDIR /src/NhiApi
RUN dotnet publish -c Release \
    -p:DebugType=portable \
    -p:DebugSymbols=true \
    -o /app/publish \
    --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip procps \
    && curl -sSL https://aka.ms/getvsdbgsh | /bin/sh /dev/stdin -v latest -l /vsdbg \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .
# PDB 與 DLL 同一次 publish；最終映像不帶 PDB，deploy 會另存供 Enable 注入
RUN rm -f /app/*.pdb

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

EXPOSE 8080
ENTRYPOINT ["dotnet", "NhiApi.dll"]
