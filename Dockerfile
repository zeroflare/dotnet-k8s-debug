# 最終映像只含應用程式：不含 PDB、不含 vsdbg。
# 除錯時用 GitHub Actions「Enable Debug Tools」手動拷入；結束可再 Remove。
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/NhiApi/NhiApi.csproj NhiApi/
RUN dotnet restore NhiApi/NhiApi.csproj

COPY src/NhiApi/ NhiApi/
WORKDIR /src/NhiApi
# 中間產物可含 PDB（供與日後 Actions 重建的符號對齊）；不會留在 final 階段
RUN dotnet publish -c Release \
    -p:DebugType=portable \
    -p:DebugSymbols=true \
    -o /app/publish \
    --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .
# 丟棄符號：跑起來的 image / pod 預設沒有 PDB
RUN rm -f /app/*.pdb

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

EXPOSE 8080
ENTRYPOINT ["dotnet", "NhiApi.dll"]
