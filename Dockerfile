# 映像內建 vsdbg + 同源 Portable PDB（預設不刪 PDB）。
# deploy 另將同源 PDB 上傳 GitHub Actions Artifact；必要時 Enable 再注入 pod。
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/NhiApi/NhiApi.csproj NhiApi/
RUN dotnet restore NhiApi/NhiApi.csproj

COPY src/NhiApi/ NhiApi/
WORKDIR /src/NhiApi
# Debug：關閉優化，遠端斷點才能停穩並改區域變數（例如 / 的 status）
RUN dotnet publish -c Debug \
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
# 保留與 DLL 同一次 publish 的 PDB（預設不刪）

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

EXPOSE 8080
ENTRYPOINT ["dotnet", "NhiApi.dll"]
