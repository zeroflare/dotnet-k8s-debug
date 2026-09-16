# Debug image：帶 Portable PDB + vsdbg，供 VS Code / Visual Studio 用 kubectl exec attach
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY src/NhiApi/NhiApi.csproj NhiApi/
RUN dotnet restore NhiApi/NhiApi.csproj

COPY src/NhiApi/ NhiApi/
WORKDIR /src/NhiApi
RUN dotnet publish -c Debug -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

# procps 提供 ps（process picker）；vsdbg 是 .NET 跨平台 debugger（stdio，不開 port）
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip procps \
    && curl -sSL https://aka.ms/getvsdbgsh | /bin/sh /dev/stdin -v latest -l /vsdbg \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Development

EXPOSE 8080
ENTRYPOINT ["dotnet", "NhiApi.dll"]
